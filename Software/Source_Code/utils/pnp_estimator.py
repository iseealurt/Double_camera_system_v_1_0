import cv2
import numpy as np

from utils import config

try:
    import torch

    _HAS_TORCH = True
except ImportError:
    _HAS_TORCH = False


class _GpuOrbMatcher:
    def __init__(self):
        self.device = None
        self.popcount_lut = None
        self._available = False
        self._init_gpu()

    def _init_gpu(self):
        if not _HAS_TORCH:
            return
        if not torch.cuda.is_available():
            return
        try:
            self.device = torch.device('cuda')
            lut = torch.zeros(256, dtype=torch.uint8, device=self.device)
            for i in range(256):
                lut[i] = bin(i).count('1')
            self.popcount_lut = lut
            self._available = True
        except Exception:
            self._available = False

    @property
    def available(self):
        return self._available and config.PNP_GPU_MATCHING_ENABLED

    def batch_hamming(self, template_des, target_des):
        t = torch.from_numpy(template_des).to(self.device, non_blocking=True)
        q = torch.from_numpy(target_des).to(self.device, non_blocking=True)
        xor = t.unsqueeze(1) ^ q.unsqueeze(0)
        dist = self.popcount_lut[xor.long()].sum(dim=2)
        return dist.cpu().numpy()

    def batch_good_matches_ratio(self, pyramid_data, target_des, max_dist):
        t = torch.from_numpy(target_des).to(self.device, non_blocking=True)
        best_ratio = 0.0
        for scale, pyr_kp, pyr_des in pyramid_data:
            if pyr_des is None or len(pyr_kp) < 4:
                continue
            p = torch.from_numpy(pyr_des).to(self.device, non_blocking=True)
            xor = p.unsqueeze(1) ^ t.unsqueeze(0)
            dist = self.popcount_lut[xor.long()].sum(dim=2)
            counts = (dist < max_dist).sum(dim=1)
            n_good = int(counts.sum().item())
            ratio = n_good / max(len(pyr_kp), 1)
            if ratio > best_ratio:
                best_ratio = ratio
        return best_ratio


class PnPProcessor:
    def __init__(self):
        self.template_image = None
        self.template_gray = None
        self.template_kp = None
        self.template_des = None
        self.pcb_width_cm = 0.0
        self.pcb_height_cm = 0.0
        self.model_3d_points = None
        self.template_loaded = False
        self.template_pyramid_data = []
        self.template_pyramid_scales = []
        self.orb = cv2.ORB_create(nfeatures=config.PNP_ORB_NFEATURES)
        self.matcher = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=True)
        self.gpu_matcher = _GpuOrbMatcher()
        self._target_center = None
        self._target_lost_counter = 0
        self._target_active = False
        self._target_just_appeared = False
        self._yolo_last_trigger_frame = -config.PNP_YOLO_TRIGGER_INTERVAL
        self._yolo_trigger_pending = False

    def set_template(self, image, width_cm, height_cm):
        h, w = image.shape[:2]
        self.template_image = image.copy()
        self.template_gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        self.pcb_width_cm = width_cm
        self.pcb_height_cm = height_cm

        self.template_pyramid_scales = config.PNP_PYRAMID_SCALES
        self.template_pyramid_data = []

        for scale in self.template_pyramid_scales:
            if abs(scale - 1.0) < 0.01:
                scaled_gray = self.template_gray
            else:
                new_w = max(int(w * scale), 32)
                new_h = max(int(h * scale), 32)
                scaled_gray = cv2.resize(self.template_gray, (new_w, new_h),
                                         interpolation=cv2.INTER_AREA)

            kp, des = self.orb.detectAndCompute(scaled_gray, None)
            if des is not None and len(kp) >= 4:
                self.template_pyramid_data.append((scale, kp, des))

        self.template_kp, self.template_des = self.template_pyramid_data[0][1:] \
            if self.template_pyramid_data else (None, None)

        half_w = width_cm / 2.0
        half_h = height_cm / 2.0
        self.model_3d_points = np.array([
            [-half_w, -half_h, 0.0],
            [half_w, -half_h, 0.0],
            [half_w, half_h, 0.0],
            [-half_w, half_h, 0.0],
        ], dtype=np.float32)

        self.template_corners = np.array([
            [0, 0],
            [w - 1, 0],
            [w - 1, h - 1],
            [0, h - 1],
        ], dtype=np.float32)

        self.template_loaded = True
        self.reset_target_tracking()

    def detect_pcb_contour(self, image):
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edged = cv2.Canny(blurred, 50, 150)

        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
        closed = cv2.morphologyEx(edged, cv2.MORPH_CLOSE, kernel)

        contours, _ = cv2.findContours(
            closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )

        if not contours:
            return None

        largest = max(contours, key=cv2.contourArea)
        area = cv2.contourArea(largest)

        min_area = image.shape[0] * image.shape[1] * config.PNP_MIN_CONTOUR_AREA_RATIO
        if area < min_area:
            return None

        peri = cv2.arcLength(largest, True)
        approx = cv2.approxPolyDP(
            largest, config.PNP_CONTOUR_APPROX_EPSILON * peri, True
        )

        if len(approx) != 4:
            return None

        corners = self._order_corners(approx.reshape(4, 2))
        return corners

    def _order_corners(self, pts):
        rect = np.zeros((4, 2), dtype=np.float32)
        s = pts.sum(axis=1)
        rect[0] = pts[np.argmin(s)]
        rect[2] = pts[np.argmax(s)]
        diff = np.diff(pts, axis=1)
        rect[1] = pts[np.argmin(diff)]
        rect[3] = pts[np.argmax(diff)]
        return rect

    def compute_similarity(self, target_gray):
        if not self.template_loaded or not self.template_pyramid_data:
            return 0.0

        target_kp, target_des = self.orb.detectAndCompute(target_gray, None)

        if target_des is None or len(target_kp) < 4:
            return 0.0

        if self.gpu_matcher.available:
            return self.gpu_matcher.batch_good_matches_ratio(
                self.template_pyramid_data,
                target_des,
                config.PNP_ORB_GOOD_MATCH_DIST,
            )

        best_similarity = 0.0
        for scale, pyr_kp, pyr_des in self.template_pyramid_data:
            if pyr_des is None or len(pyr_kp) < 4:
                continue
            matches = self.matcher.match(pyr_des, target_des)
            if not matches:
                continue
            good_matches = [m for m in matches
                            if m.distance < config.PNP_ORB_GOOD_MATCH_DIST]
            n_template_kp = max(len(pyr_kp), 1)
            similarity = len(good_matches) / n_template_kp
            if similarity > best_similarity:
                best_similarity = similarity

        return best_similarity

    def mechanical_match(self, image, frame_index):
        if not self.template_loaded:
            return None

        corners = self.detect_pcb_contour(image)
        if corners is None:
            self._update_target_state(None, frame_index)
            return None

        center = corners.mean(axis=0)
        similarity = self.compute_similarity(
            cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        )

        if similarity < config.PNP_SIMILARITY_THRESHOLD:
            self._update_target_state(None, frame_index)
            return None

        result = {
            "corners": corners,
            "center": center,
            "similarity": similarity,
        }

        self._update_target_state(result, frame_index)

        if self._is_new_target():
            self._yolo_trigger_pending = True
            self._yolo_last_trigger_frame = frame_index

        if self._should_trigger_yolo(frame_index):
            self._yolo_trigger_pending = True
            self._yolo_last_trigger_frame = frame_index

        return result

    def _update_target_state(self, match_result, frame_index):
        if match_result is None:
            self._target_lost_counter += 1
            if self._target_lost_counter >= config.PNP_TARGET_LOST_FRAMES:
                self._target_active = False
                self._target_center = None
                self._target_just_appeared = False
        else:
            was_active = self._target_active
            self._target_lost_counter = 0
            self._target_center = match_result["center"]
            self._target_active = True
            self._target_just_appeared = not was_active

    def _is_new_target(self):
        if not self._target_just_appeared:
            return False
        self._target_just_appeared = False
        return True

    def _should_trigger_yolo(self, frame_index):
        if not self._target_active:
            return False
        frames_since = frame_index - self._yolo_last_trigger_frame
        return frames_since >= config.PNP_YOLO_TRIGGER_INTERVAL

    def check_yolo_trigger(self):
        if self._yolo_trigger_pending:
            self._yolo_trigger_pending = False
            return True
        return False

    def set_from_yolo_bbox(self, bbox):
        if not self.template_loaded:
            return False
        x1, y1, x2, y2 = bbox
        corners = np.array([
            [x1, y1],
            [x2, y1],
            [x2, y2],
            [x1, y2],
        ], dtype=np.float32)
        self._yolo_corners = self._order_corners(corners)
        return True

    def yolo_match(self, image, yolo_detection):
        if not self.template_loaded or yolo_detection is None:
            self._update_target_state(None, 0)
            return None

        bbox = yolo_detection['bbox']
        self.set_from_yolo_bbox(bbox)

        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        similarity = self.compute_similarity(gray)

        if similarity >= config.PNP_SIMILARITY_THRESHOLD:
            result = {
                "corners": self._yolo_corners,
                "center": self._yolo_corners.mean(axis=0),
                "similarity": similarity,
            }
            self._update_target_state(result, 0)
            return result

        self._update_target_state(None, 0)
        return None

    def reset_target_tracking(self):
        self._target_center = None
        self._target_lost_counter = 0
        self._target_active = False
        self._target_just_appeared = False
        self._yolo_last_trigger_frame = -config.PNP_YOLO_TRIGGER_INTERVAL
        self._yolo_trigger_pending = False
        self._yolo_corners = None

    def estimate_pose(self, target_corners):
        if not self.template_loaded:
            return None

        camera_matrix = self._get_camera_matrix()

        success, rvec, tvec = cv2.solvePnP(
            self.model_3d_points,
            target_corners.astype(np.float32),
            camera_matrix,
            config.PNP_DIST_COEFFS,
            flags=cv2.SOLVEPNP_ITERATIVE,
        )

        if not success:
            return None

        R, _ = cv2.Rodrigues(rvec)
        azimuth, elevation = self._compute_spherical_angles(R, tvec)

        return {
            "rvec": rvec,
            "tvec": tvec,
            "R": R,
            "azimuth": azimuth,
            "elevation": elevation,
            "corners": target_corners,
        }

    def _get_camera_matrix(self):
        fx = config.STEREO_FOCAL_LENGTH_PX
        fy = config.STEREO_FOCAL_LENGTH_PX
        cx = config.PCD_PARAMS["CAM_CX"]
        cy = config.PCD_PARAMS["CAM_CY"]
        return np.array([
            [fx, 0, cx],
            [0, fy, cy],
            [0, 0, 1],
        ], dtype=np.float32)

    def _compute_spherical_angles(self, R, tvec):
        z_axis = R[:, 2]
        azimuth = np.degrees(np.arctan2(z_axis[0], -z_axis[2]))
        elevation = np.degrees(
            np.arcsin(z_axis[1] / max(np.linalg.norm(z_axis), 1e-8))
        )
        return azimuth, elevation

    def draw_pose(self, image, pose_result):
        if pose_result is None:
            return image

        result = image.copy()
        rvec = pose_result["rvec"]
        tvec = pose_result["tvec"]
        corners = pose_result["corners"]
        azimuth = pose_result["azimuth"]
        elevation = pose_result["elevation"]

        camera_matrix = self._get_camera_matrix()

        pts = corners.astype(np.int32).reshape((-1, 1, 2))
        cv2.polylines(result, [pts], True, config.PNP_PCB_OUTLINE_COLOR, 3)

        for i, corner in enumerate(corners):
            cx, cy = int(corner[0]), int(corner[1])
            cv2.circle(result, (cx, cy), 5, (0, 0, 255), -1)

        axis_len = max(self.pcb_width_cm, self.pcb_height_cm) * config.PNP_DRAW_AXIS_LENGTH_RATIO
        axis_pts_3d = np.float32([
            [0, 0, 0],
            [axis_len, 0, 0],
            [0, axis_len, 0],
            [0, 0, axis_len],
        ]).reshape(-1, 3)
        img_pts, _ = cv2.projectPoints(
            axis_pts_3d, rvec, tvec, camera_matrix, config.PNP_DIST_COEFFS
        )
        img_pts = img_pts.reshape(-1, 2).astype(np.int32)
        origin = tuple(img_pts[0])

        colors = [(0, 0, 255), (0, 255, 0), (255, 0, 0)]
        labels = ['X', 'Y', 'Z']
        for i, (pt, color, label) in enumerate(zip(img_pts[1:], colors, labels)):
            cv2.arrowedLine(result, origin, tuple(pt), color, 3, tipLength=0.2)
            label_pt = (int(pt[0] + 5), int(pt[1] + 5))
            cv2.putText(result, label, label_pt, cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)

        normal_end_3d = np.float32([[0, 0, axis_len * config.PNP_DRAW_NORMAL_LENGTH_RATIO]])
        normal_end_2d, _ = cv2.projectPoints(
            normal_end_3d, rvec, tvec, camera_matrix, config.PNP_DIST_COEFFS
        )
        normal_end_2d = tuple(normal_end_2d.reshape(-1, 2).astype(np.int32)[0])
        cv2.arrowedLine(result, origin, normal_end_2d, (255, 0, 255), 3, tipLength=0.3)

        overlay = result.copy()
        x0, y0 = 10, 10
        line_h = 25
        box_w = 220
        box_h = 2 * line_h + 10
        cv2.rectangle(overlay, (x0, y0), (x0 + box_w, y0 + box_h), (0, 0, 0), -1)
        cv2.addWeighted(overlay, 0.6, result, 0.4, 0, result)

        info_lines = [
            f"Azimuth: {azimuth:+7.1f} deg",
            f"Elevation: {elevation:+5.1f} deg",
        ]
        for i, line in enumerate(info_lines):
            cv2.putText(
                result, line,
                (x0 + 10, y0 + 20 + i * line_h),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 255), 2,
            )

        return result
