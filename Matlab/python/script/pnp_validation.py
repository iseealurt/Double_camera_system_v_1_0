import sys
import os
import time
import csv
import cv2
import numpy as np


PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
DATA_DIR = os.path.join(PROJECT_ROOT, 'Software', 'datasheet', 'pose estimation')
OUTPUT_DIR = os.path.join(PROJECT_ROOT, 'Matlab', 'python', 'script', 'output')
TEMPLATE_PATH = os.path.join(DATA_DIR, 'template.jpg')
IMAGE_PATHS = [os.path.join(DATA_DIR, f'{i}.jpg') for i in range(1, 7)]

PCB_WIDTH_CM = 18.0
PCB_HEIGHT_CM = 10.0

PHONE_POSE_DATA = {
    "1.jpg": {"x_deg": 35.7, "y_deg": 7.0, "z_deg": 83.5},
    "2.jpg": {"x_deg": 45.5, "y_deg": -1.3, "z_deg": 80.8},
    "3.jpg": {"x_deg": 34.5, "y_deg": -1.5, "z_deg": 56.8},
}

sys.path.insert(0, os.path.join(PROJECT_ROOT, 'Software', 'Source_Code'))

from utils.pnp_estimator import PnPProcessor
from utils import config


_SIFT_AVAILABLE = False
try:
    _sift = cv2.SIFT_create(nfeatures=3000)
    _SIFT_AVAILABLE = True
except Exception:
    try:
        _sift = cv2.xfeatures2d.SIFT_create(nfeatures=3000)
        _SIFT_AVAILABLE = True
    except Exception:
        _sift = None


def load_images():
    template = cv2.imdecode(np.fromfile(TEMPLATE_PATH, dtype=np.uint8), cv2.IMREAD_COLOR)
    if template is None:
        raise FileNotFoundError(f"Cannot load template image: {TEMPLATE_PATH}")

    targets = []
    for path in IMAGE_PATHS:
        img = cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_COLOR)
        if img is None:
            raise FileNotFoundError(f"Cannot load target image: {path}")
        targets.append((os.path.basename(path), img))

    return template, targets


def _extract_sift_features(gray_img):
    if not _SIFT_AVAILABLE:
        return None, None
    try:
        kp, des = _sift.detectAndCompute(gray_img, None)
        return kp, des
    except Exception:
        return None, None


def _match_with_homography(src_kp, src_des, dst_kp, dst_des,
                           src_h, src_w, norm_type, ratio_thresh=0.75):
    if src_des is None or dst_des is None or len(src_kp) < 4 or len(dst_kp) < 4:
        return None, 0.0, 0

    bf = cv2.BFMatcher(norm_type, crossCheck=False)
    raw_matches = bf.knnMatch(src_des, dst_des, k=2)

    good_matches = []
    for match_pair in raw_matches:
        if len(match_pair) < 2:
            continue
        m, n = match_pair[0], match_pair[1]
        if m.distance < ratio_thresh * n.distance:
            good_matches.append(m)

    similarity = len(good_matches) / max(len(src_kp), 1)

    if len(good_matches) < 4:
        return None, similarity, len(good_matches)

    src_pts = np.float32([src_kp[m.queryIdx].pt for m in good_matches]).reshape(-1, 1, 2)
    dst_pts = np.float32([dst_kp[m.trainIdx].pt for m in good_matches]).reshape(-1, 1, 2)

    H, mask = cv2.findHomography(src_pts, dst_pts, cv2.RANSAC, 5.0)
    if H is None:
        return None, similarity, len(good_matches)

    inliers = int(mask.sum()) if mask is not None else 0
    if inliers < 6:
        return None, similarity, len(good_matches)

    template_corners = np.float32([[0, 0], [src_w - 1, 0],
                                   [src_w - 1, src_h - 1], [0, src_h - 1]]).reshape(-1, 1, 2)
    projected_corners = cv2.perspectiveTransform(template_corners, H).reshape(4, 2)

    s = projected_corners.sum(axis=1)
    diff = np.diff(projected_corners, axis=1)
    ordered = np.zeros((4, 2), dtype=np.float32)
    ordered[0] = projected_corners[np.argmin(s)]
    ordered[2] = projected_corners[np.argmax(s)]
    ordered[1] = projected_corners[np.argmin(diff)]
    ordered[3] = projected_corners[np.argmax(diff)]

    center = ordered.mean(axis=0)

    return {
        "corners": ordered,
        "center": center,
        "similarity": similarity,
    }, similarity, inliers


def _try_orb_pyramid_match(processor, target_image):
    target_gray = cv2.cvtColor(target_image, cv2.COLOR_BGR2GRAY)
    target_kp, target_des = processor.orb.detectAndCompute(target_gray, None)

    if target_des is None or len(target_kp) < 4:
        return None, 0.0, 0

    best_result = None
    best_score = 0.0
    best_good = 0

    for scale, pyr_kp, pyr_des in processor.template_pyramid_data:
        if pyr_des is None or len(pyr_kp) < 4:
            continue
        h, w = int(processor.template_gray.shape[0] * scale), int(processor.template_gray.shape[1] * scale)
        result, sim, good = _match_with_homography(
            pyr_kp, pyr_des, target_kp, target_des,
            h, w, cv2.NORM_HAMMING, ratio_thresh=0.80
        )
        if result is not None and sim > best_score:
            best_result = result
            best_score = sim
            best_good = good

    return best_result, best_score, best_good


def _resize_for_fast_matching(gray_img, max_dim=1200):
    h, w = gray_img.shape[:2]
    if max(h, w) <= max_dim:
        return gray_img, 1.0
    scale = max_dim / max(h, w)
    new_w = int(w * scale)
    new_h = int(h * scale)
    return cv2.resize(gray_img, (new_w, new_h), interpolation=cv2.INTER_AREA), scale


def _try_sift_with_scale(processor, target_image, ratio_thresh=0.75, max_dim=1200):
    template_gray, t_scale = _resize_for_fast_matching(processor.template_gray, max_dim)
    target_gray, q_scale = _resize_for_fast_matching(
        cv2.cvtColor(target_image, cv2.COLOR_BGR2GRAY), max_dim
    )

    tkp, tdes = _extract_sift_features(template_gray)
    qkp, qdes = _extract_sift_features(target_gray)

    if tkp is None or qkp is None or len(tkp) < 4 or len(qkp) < 4:
        return None, 0.0, 0

    rh, rw = template_gray.shape[:2]
    result, sim, inliers = _match_with_homography(
        tkp, tdes, qkp, qdes, rh, rw, cv2.NORM_L2, ratio_thresh
    )

    if result is not None:
        result["corners"] = result["corners"] / q_scale
        result["center"] = result["center"] / q_scale

    return result, sim, inliers


def match_template(processor, target_image, frame_index, img_name):
    match_result = processor.mechanical_match(target_image, frame_index)
    if match_result is not None:
        print(f"  [{img_name}] contour-based match OK (similarity={match_result['similarity']:.4f})")
        return match_result

    if _SIFT_AVAILABLE:
        print(f"  [{img_name}] contour-based match failed, trying SIFT homography ...")
        match_result, sift_sim, sift_inliers = _try_sift_with_scale(processor, target_image, ratio_thresh=0.75)
        if match_result is not None:
            print(f"  [{img_name}] SIFT homography OK (similarity={sift_sim:.4f}, inliers={sift_inliers})")
            return match_result

        print(f"  [{img_name}] SIFT ratio=0.75 failed (sim={sift_sim:.4f}, inliers={sift_inliers}), trying ratio=0.85 ...")
        match_result, sift_sim, sift_inliers = _try_sift_with_scale(processor, target_image, ratio_thresh=0.85)
        if match_result is not None:
            print(f"  [{img_name}] SIFT ratio=0.85 OK (similarity={sift_sim:.4f}, inliers={sift_inliers})")
            return match_result

        print(f"  [{img_name}] SIFT all thresholds failed")

    print(f"  [{img_name}] trying ORB pyramid homography ...")
    match_result, orbp_sim, orbp_good = _try_orb_pyramid_match(processor, target_image)
    if match_result is not None:
        print(f"  [{img_name}] ORB pyramid homography OK (similarity={orbp_sim:.4f}, inliers={orbp_good})")
        return match_result
    print(f"  [{img_name}] ORB pyramid homography failed (similarity={orbp_sim:.4f}, inliers={orbp_good})")

    print(f"  [{img_name}] all matching strategies failed")
    return None


def estimate_pose_from_match(processor, match_result, img_name):
    if match_result is None:
        return None
    corners = match_result["corners"]
    pose_result = processor.estimate_pose(corners)
    if pose_result is None:
        print(f"  [{img_name}] WARNING: solvePnP failed")
    return pose_result


def compute_reprojection_error(processor, pose_result):
    if pose_result is None:
        return None
    camera_matrix = processor._get_camera_matrix()
    projected, _ = cv2.projectPoints(
        processor.model_3d_points,
        pose_result["rvec"],
        pose_result["tvec"],
        camera_matrix,
        config.PNP_DIST_COEFFS,
    )
    projected = projected.reshape(-1, 2)
    corners = pose_result["corners"]
    errors = np.linalg.norm(projected - corners, axis=1)
    return {
        "mean_error_px": float(np.mean(errors)),
        "max_error_px": float(np.max(errors)),
        "per_corner_errors_px": errors.tolist(),
    }


def compute_matching_accuracy(processor, target_image):
    target_gray = cv2.cvtColor(target_image, cv2.COLOR_BGR2GRAY)
    target_kp, target_des = processor.orb.detectAndCompute(target_gray, None)
    if target_des is None or len(target_kp) < 4:
        return None

    matches = processor.matcher.match(processor.template_des, target_des)
    good_matches = [m for m in matches if m.distance < config.PNP_ORB_GOOD_MATCH_DIST]

    return {
        "total_matches": len(matches),
        "good_matches": len(good_matches),
        "template_kp_count": len(processor.template_kp),
        "target_kp_count": len(target_kp),
        "good_match_ratio": len(good_matches) / max(len(processor.template_kp), 1),
        "mean_match_distance": float(np.mean([m.distance for m in matches])) if matches else 0.0,
    }


def rotation_matrix_to_euler(R):
    pitch = np.degrees(np.arcsin(-R[2, 0]))

    if np.cos(np.radians(pitch)) > 1e-8:
        roll = np.degrees(np.arctan2(R[2, 1], R[2, 2]))
        yaw = np.degrees(np.arctan2(R[1, 0], R[0, 0]))
    else:
        roll = 0.0
        yaw = np.degrees(np.arctan2(-R[0, 1], R[1, 1]))

    return {
        "roll_deg": float(roll),
        "pitch_deg": float(pitch),
        "yaw_deg": float(yaw),
    }


def compute_attitude(pose_result):
    if pose_result is None:
        return None
    euler = rotation_matrix_to_euler(pose_result["R"])
    return {
        "roll_deg": euler["roll_deg"],
        "pitch_deg": euler["pitch_deg"],
        "yaw_deg": euler["yaw_deg"],
        "azimuth_deg": float(pose_result["azimuth"]),
        "elevation_deg": float(pose_result["elevation"]),
    }


def compute_translation_error(pose_result, pcb_width_cm, pcb_height_cm):
    if pose_result is None:
        return None
    tvec = pose_result["tvec"].flatten()
    dist_cm = float(np.linalg.norm(tvec))
    pcb_diag_cm = np.sqrt(pcb_width_cm ** 2 + pcb_height_cm ** 2)
    return {
        "distance_cm": dist_cm,
        "tvec_x_cm": float(tvec[0]),
        "tvec_y_cm": float(tvec[1]),
        "tvec_z_cm": float(tvec[2]),
        "pcb_diag_cm": pcb_diag_cm,
    }


def euler_zyx_to_matrix(x_deg, y_deg, z_deg):
    rx = np.radians(x_deg)
    ry = np.radians(y_deg)
    rz = np.radians(z_deg)

    Rx = np.array([
        [1, 0, 0],
        [0, np.cos(rx), -np.sin(rx)],
        [0, np.sin(rx), np.cos(rx)],
    ])
    Ry = np.array([
        [np.cos(ry), 0, np.sin(ry)],
        [0, 1, 0],
        [-np.sin(ry), 0, np.cos(ry)],
    ])
    Rz = np.array([
        [np.cos(rz), -np.sin(rz), 0],
        [np.sin(rz), np.cos(rz), 0],
        [0, 0, 1],
    ])

    return Rz @ Ry @ Rx


R_CAMERA_ON_PHONE_INITIAL = np.array([
    [1, 0, 0],
    [0, -1, 0],
    [0, 0, -1],
], dtype=np.float64)

R_CAMERA_ON_PHONE = R_CAMERA_ON_PHONE_INITIAL.copy()
_CAM_CALIBRATED = False


def calibrate_camera_on_phone(img_name, pose_result):
    global R_CAMERA_ON_PHONE, _CAM_CALIBRATED
    if _CAM_CALIBRATED:
        return
    phone_data = PHONE_POSE_DATA.get(img_name)
    if phone_data is None or pose_result is None:
        return
    R_phone = euler_zyx_to_matrix(phone_data["x_deg"],
                                  phone_data["y_deg"],
                                  phone_data["z_deg"])
    R_CAMERA_ON_PHONE = R_phone @ pose_result["R"].T
    _CAM_CALIBRATED = True
    cal_euler = rotation_matrix_to_euler(R_CAMERA_ON_PHONE)
    print(f"\n  [CALIBRATED] R_CAMERA_ON_PHONE from [{img_name}]:")
    print(f"    Roll={cal_euler['roll_deg']:+7.1f} deg, "
          f"Pitch={cal_euler['pitch_deg']:+7.1f} deg, "
          f"Yaw={cal_euler['yaw_deg']:+7.1f} deg")


def compute_pcb_world_pose(img_name, pose_result):
    if pose_result is None:
        return None
    phone_data = PHONE_POSE_DATA.get(img_name)
    if phone_data is None:
        return None

    R_phone = euler_zyx_to_matrix(phone_data["x_deg"],
                                  phone_data["y_deg"],
                                  phone_data["z_deg"])

    R_pcb_world = R_phone.T @ R_CAMERA_ON_PHONE @ pose_result["R"]
    euler = rotation_matrix_to_euler(R_pcb_world)

    return {
        "roll_deg": euler["roll_deg"],
        "pitch_deg": euler["pitch_deg"],
        "yaw_deg": euler["yaw_deg"],
    }


def save_visualization(processor, target_image, pose_result, match_result, output_path):
    vis_image = target_image.copy()

    if match_result is not None:
        corners = match_result["corners"]
        pts = corners.astype(np.int32).reshape((-1, 1, 2))
        cv2.polylines(vis_image, [pts], True, (0, 255, 255), 3)
        for i, corner in enumerate(corners):
            cx, cy = int(corner[0]), int(corner[1])
            cv2.circle(vis_image, (cx, cy), 5, (0, 0, 255), -1)

    if pose_result is not None:
        rvec = pose_result["rvec"]
        tvec = pose_result["tvec"]
        camera_matrix = processor._get_camera_matrix()
        axis_len = max(PCB_WIDTH_CM, PCB_HEIGHT_CM) * 0.3
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
        for pt, color, label in zip(img_pts[1:], colors, labels):
            cv2.arrowedLine(vis_image, origin, tuple(pt), color, 3, tipLength=0.2)
            cv2.putText(vis_image, label, (int(pt[0] + 5), int(pt[1] + 5)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)

        attitude = compute_attitude(pose_result)
        if attitude is not None:
            info_lines = [
                f"Azimuth: {attitude['azimuth_deg']:+7.1f} deg",
                f"Elevation: {attitude['elevation_deg']:+5.1f} deg",
                f"Roll : {attitude['roll_deg']:+7.1f}  Pitch: {attitude['pitch_deg']:+7.1f}  Yaw: {attitude['yaw_deg']:+7.1f}",
            ]
            for i, line in enumerate(info_lines):
                cv2.putText(vis_image, line, (10, 30 + i * 25),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 255, 255), 2)

    if match_result is not None:
        sim_text = f"Similarity: {match_result['similarity']:.3f}"
        cv2.putText(vis_image, sim_text, (10, vis_image.shape[0] - 20),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    cv2.imencode('.jpg', vis_image)[1].tofile(output_path)


def print_summary(results):
    print("\n" + "=" * 110)
    print("PnP Validation Results Summary")
    print("=" * 110)

    header = (f"{'Image':<10} {'Match':<8} {'Similarity':<12} "
              f"{'Dist(cm)':<10} {'ReprojErr(px)':<15} {'Time(ms)':<10}")
    print(header)
    print("-" * 110)

    for r in results:
        name = r["image"]
        matched = "OK" if r["match_success"] else "FAIL"
        sim = f"{r['similarity']:.4f}" if r["similarity"] is not None else "N/A"
        dist = f"{r['distance_cm']:.2f}" if r["distance_cm"] is not None else "N/A"
        rerr = f"{r['reproj_error_mean_px']:.2f}" if r["reproj_error_mean_px"] is not None else "N/A"
        t = f"{r['time_ms']:.1f}" if r["time_ms"] is not None else "N/A"
        print(f"{name:<10} {matched:<8} {sim:<12} {dist:<10} {rerr:<15} {t:<10}")

    print("\n" + "-" * 110)
    print("Attitude Angles (Spherical + Euler ZYX)")
    print("-" * 110)

    att_header = (f"{'Image':<10} {'Azimuth(deg)':<14} {'Elev(deg)':<11} "
                  f"{'Roll(deg)':<12} {'Pitch(deg)':<12} {'Yaw(deg)':<12}")
    print(att_header)
    print("-" * 110)

    for r in results:
        name = r["image"]
        az = f"{r['azimuth_deg']:+7.1f}" if r["azimuth_deg"] is not None else "N/A"
        el = f"{r['elevation_deg']:+7.1f}" if r["elevation_deg"] is not None else "N/A"
        roll = f"{r['roll_deg']:+7.1f}" if r["roll_deg"] is not None else "N/A"
        pitch = f"{r['pitch_deg']:+7.1f}" if r["pitch_deg"] is not None else "N/A"
        yaw = f"{r['yaw_deg']:+7.1f}" if r["yaw_deg"] is not None else "N/A"
        print(f"{name:<10} {az:<14} {el:<11} {roll:<12} {pitch:<12} {yaw:<12}")

    print("-" * 110)

    pcb_data = [(r["image"], r["pcb_world_roll_deg"], r["pcb_world_pitch_deg"], r["pcb_world_yaw_deg"])
                for r in results if r["pcb_world_roll_deg"] is not None]
    if pcb_data:
        print("\n" + "-" * 110)
        print("Actual PCB World Pose (Phone Pose Compensated, Euler ZYX)")
        print("-" * 110)
        pcb_header = f"{'Image':<10} {'Roll(deg)':<14} {'Pitch(deg)':<14} {'Yaw(deg)':<14}"
        print(pcb_header)
        print("-" * 110)
        for name, wr, wp, wy in pcb_data:
            wr_s = f"{wr:+7.1f}" if wr is not None else "N/A"
            wp_s = f"{wp:+7.1f}" if wp is not None else "N/A"
            wy_s = f"{wy:+7.1f}" if wy is not None else "N/A"
            print(f"{name:<10} {wr_s:<14} {wp_s:<14} {wy_s:<14}")
        print("-" * 110)
    else:
        print("\nActual PCB World Pose: N/A (no phone pose data available)")

    match_ok = sum(1 for r in results if r["match_success"])
    pose_ok = sum(1 for r in results if r["pose_success"])
    print(f"\nMatch success: {match_ok}/{len(results)}  |  Pose estimation success: {pose_ok}/{len(results)}")

    reproj_errors = [r["reproj_error_mean_px"] for r in results if r["reproj_error_mean_px"] is not None]
    if reproj_errors:
        print(f"Reprojection error - mean: {np.mean(reproj_errors):.3f} px, "
              f"min: {np.min(reproj_errors):.3f} px, max: {np.max(reproj_errors):.3f} px")
    else:
        print("Reprojection error: N/A (no successful pose estimations)")

    sims = [r["similarity"] for r in results if r["similarity"] is not None]
    if sims:
        print(f"Similarity - mean: {np.mean(sims):.4f}, min: {np.min(sims):.4f}, max: {np.max(sims):.4f}")

    dists = [r["distance_cm"] for r in results if r["distance_cm"] is not None]
    if dists:
        print(f"Distance - mean: {np.mean(dists):.2f} cm, min: {np.min(dists):.2f} cm, max: {np.max(dists):.2f} cm")

    print("=" * 110)


def save_csv(results, output_dir):
    csv_path = os.path.join(output_dir, "validation_results.csv")
    try:
        os.remove(csv_path)
    except OSError:
        pass
    fieldnames = [
        "image", "match_success", "pose_success", "similarity",
        "azimuth_deg", "elevation_deg", "roll_deg", "pitch_deg", "yaw_deg",
        "pcb_world_roll_deg", "pcb_world_pitch_deg", "pcb_world_yaw_deg",
        "distance_cm",
        "tvec_x_cm", "tvec_y_cm", "tvec_z_cm",
        "reproj_error_mean_px", "reproj_error_max_px",
        "good_matches", "total_matches", "good_match_ratio",
        "mean_match_distance", "time_ms",
    ]
    with open(csv_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(results)
    print(f"\nCSV results saved to: {csv_path}")


def main():
    print("=" * 60)
    print("PnP Algorithm Validation Script")
    print("=" * 60)
    print(f"Template: {TEMPLATE_PATH}")
    print(f"PCB dimensions: {PCB_WIDTH_CM}cm x {PCB_HEIGHT_CM}cm")
    print(f"Output: {OUTPUT_DIR}")
    print(f"SIFT available: {_SIFT_AVAILABLE}")
    print("-" * 60)

    template, targets = load_images()
    print(f"Template loaded: {template.shape[1]}x{template.shape[0]}")
    for img_name, img in targets:
        print(f"  Target [{img_name}]: {img.shape[1]}x{img.shape[0]}")

    processor = PnPProcessor()
    processor.set_template(template, PCB_WIDTH_CM, PCB_HEIGHT_CM)
    print(f"Template features: {len(processor.template_kp)} ORB keypoints, "
          f"{len(processor.template_pyramid_data)} pyramid levels")

    if _SIFT_AVAILABLE:
        t_gray = processor.template_gray
        tkp, _ = _extract_sift_features(t_gray)
        if tkp is not None:
            print(f"Template SIFT features: {len(tkp)} keypoints")

    results = []

    for idx, (img_name, target_image) in enumerate(targets):
        print(f"\n--- Processing [{img_name}] ({idx + 1}/{len(targets)}) ---")

        t0 = time.perf_counter()

        match_result = match_template(processor, target_image, idx, img_name)

        match_accuracy = compute_matching_accuracy(processor, target_image)
        if match_accuracy is not None:
            print(f"  [{img_name}] ORB stats: {match_accuracy['good_matches']}/{match_accuracy['total_matches']} good "
                  f"(ratio={match_accuracy['good_match_ratio']:.3f}, mean_dist={match_accuracy['mean_match_distance']:.1f})")

        pose_result = estimate_pose_from_match(processor, match_result, img_name)

        reproj_error = compute_reprojection_error(processor, pose_result)
        if reproj_error is not None:
            print(f"  [{img_name}] Reprojection error: mean={reproj_error['mean_error_px']:.3f} px, "
                  f"max={reproj_error['max_error_px']:.3f} px")

        attitude = compute_attitude(pose_result)
        trans_error = compute_translation_error(pose_result, PCB_WIDTH_CM, PCB_HEIGHT_CM)

        calibrate_camera_on_phone(img_name, pose_result)
        pcb_world = compute_pcb_world_pose(img_name, pose_result)

        if attitude and trans_error:
            print(f"  [{img_name}] Pose: dist={trans_error['distance_cm']:.2f} cm, "
                  f"tvec=({trans_error['tvec_x_cm']:.2f}, {trans_error['tvec_y_cm']:.2f}, {trans_error['tvec_z_cm']:.2f})")
            print(f"  [{img_name}] Spherical: Az={attitude['azimuth_deg']:+7.1f} deg, "
                  f"El={attitude['elevation_deg']:+7.1f} deg")
            print(f"  [{img_name}] Euler ZYX: Roll={attitude['roll_deg']:+7.1f} deg, "
                  f"Pitch={attitude['pitch_deg']:+7.1f} deg, Yaw={attitude['yaw_deg']:+7.1f} deg")
            if pcb_world:
                print(f"  [{img_name}] PCB World: Roll={pcb_world['roll_deg']:+7.1f} deg, "
                      f"Pitch={pcb_world['pitch_deg']:+7.1f} deg, Yaw={pcb_world['yaw_deg']:+7.1f} deg")

        t1 = time.perf_counter()
        elapsed_ms = (t1 - t0) * 1000.0
        print(f"  [{img_name}] Time: {elapsed_ms:.1f} ms")

        out_path = os.path.join(OUTPUT_DIR, f"result_{img_name}")
        save_visualization(processor, target_image, pose_result, match_result, out_path)
        print(f"  [{img_name}] Visualization saved: {out_path}")

        result = {
            "image": img_name,
            "match_success": match_result is not None,
            "pose_success": pose_result is not None,
            "similarity": match_result["similarity"] if match_result else None,
            "azimuth_deg": attitude["azimuth_deg"] if attitude else None,
            "elevation_deg": attitude["elevation_deg"] if attitude else None,
            "roll_deg": attitude["roll_deg"] if attitude else None,
            "pitch_deg": attitude["pitch_deg"] if attitude else None,
            "yaw_deg": attitude["yaw_deg"] if attitude else None,
            "pcb_world_roll_deg": pcb_world["roll_deg"] if pcb_world else None,
            "pcb_world_pitch_deg": pcb_world["pitch_deg"] if pcb_world else None,
            "pcb_world_yaw_deg": pcb_world["yaw_deg"] if pcb_world else None,
            "distance_cm": trans_error["distance_cm"] if trans_error else None,
            "tvec_x_cm": trans_error["tvec_x_cm"] if trans_error else None,
            "tvec_y_cm": trans_error["tvec_y_cm"] if trans_error else None,
            "tvec_z_cm": trans_error["tvec_z_cm"] if trans_error else None,
            "reproj_error_mean_px": reproj_error["mean_error_px"] if reproj_error else None,
            "reproj_error_max_px": reproj_error["max_error_px"] if reproj_error else None,
            "good_matches": match_accuracy["good_matches"] if match_accuracy else None,
            "total_matches": match_accuracy["total_matches"] if match_accuracy else None,
            "good_match_ratio": match_accuracy["good_match_ratio"] if match_accuracy else None,
            "mean_match_distance": match_accuracy["mean_match_distance"] if match_accuracy else None,
            "time_ms": elapsed_ms,
        }
        results.append(result)

    print_summary(results)
    save_csv(results, OUTPUT_DIR)

    print("\nDone.")


if __name__ == "__main__":
    main()
