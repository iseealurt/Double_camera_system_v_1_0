import cv2
import numpy as np
import torch
import torch.nn.functional as F

from utils import config
from utils.pcb_detector import CLASS_COLORS


_gpu_device = None
_jet_table_gpu = None


def _ensure_gpu():
    global _gpu_device
    if _gpu_device is None:
        if torch.cuda.is_available():
            _gpu_device = torch.device("cuda")
        else:
            _gpu_device = torch.device("cpu")
    return _gpu_device


def _get_jet_table(device=None):
    global _jet_table_gpu
    if _jet_table_gpu is None:
        lut = np.arange(256, dtype=np.uint8).reshape(256, 1)
        jet_bgr = cv2.applyColorMap(lut, cv2.COLORMAP_JET).squeeze(1)
        jet_rgb = jet_bgr[:, ::-1].astype(np.float32)
        _jet_table_gpu = jet_rgb
    if device is not None:
        return torch.from_numpy(_jet_table_gpu).to(device)
    return _jet_table_gpu


def crop_480p(frame, h_offset, v_offset):
    if frame is None:
        return None
    return frame[v_offset:v_offset + config.CROP_HEIGHT, h_offset:h_offset + config.CROP_WIDTH]


def crop_left_camera(frame):
    return crop_480p(
        frame,
        config.FPGA_PARAMS["CMR_1_DISP_AREA_H_OFST"],
        config.FPGA_PARAMS["CMR_1_DISP_AREA_V_OFST"],
    )


def crop_right_camera(frame):
    return crop_480p(
        frame,
        config.FPGA_PARAMS["CMR_2_DISP_AREA_H_OFST"],
        config.FPGA_PARAMS["CMR_2_DISP_AREA_V_OFST"],
    )


def draw_crop_regions(frame):
    overlay = frame.copy()
    x1, y1 = config.FPGA_PARAMS["CMR_1_DISP_AREA_H_OFST"], config.FPGA_PARAMS["CMR_1_DISP_AREA_V_OFST"]
    x2, y2 = config.FPGA_PARAMS["CMR_2_DISP_AREA_H_OFST"], config.FPGA_PARAMS["CMR_2_DISP_AREA_V_OFST"]

    cv2.rectangle(overlay, (x1, y1), (x1 + config.CROP_WIDTH, y1 + config.CROP_HEIGHT), (0, 255, 0), 2)
    cv2.putText(overlay, "Left", (x1, y1 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 255, 0), 2)

    cv2.rectangle(overlay, (x2, y2), (x2 + config.CROP_WIDTH, y2 + config.CROP_HEIGHT), (0, 0, 255), 2)
    cv2.putText(overlay, "Right", (x2, y2 - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)

    return overlay


def validate_frame(frame):
    if frame is None:
        return False
    h, w = frame.shape[:2]
    return w == config.FRAME_WIDTH and h == config.FRAME_HEIGHT


def draw_pcb_board_detection(frame, detection, distance=None, disparity_available=True):
    result = frame.copy()
    if detection is None:
        return result

    x1, y1, x2, y2 = detection['bbox']
    conf = detection['confidence']
    color = config.PCB_BOARD_DETECT_COLOR

    cv2.rectangle(result, (x1, y1), (x2, y2), color, 3)

    label = f"PCB Board {conf:.2f}"

    if not disparity_available:
        label += f" | {config.NO_DISPARITY_LABEL}"
    elif distance is not None and config.DISTANCE_VALID_MIN_CM <= distance <= config.DISTANCE_VALID_MAX_CM:
        if distance < 100.0:
            label += f" | {distance:.1f}cm"
        else:
            label += f" | {distance/100:.2f}m"
    else:
        label += f" | {config.DISTANCE_INVALID_LABEL}"

    (tw, th), baseline = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 2)
    cv2.rectangle(
        result,
        (x1, y1 - th - baseline - 4),
        (x1 + tw, y1),
        color,
        -1,
    )
    cv2.putText(
        result,
        label,
        (x1, y1 - baseline - 2),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.5,
        (0, 0, 0),
        2,
    )

    return result


def draw_pcb_detections(frame, detections, distances=None, disparity_available=True):
    result = frame.copy()
    baseline_cm = config.STEREO_PARAMS["BASELINE_CM"]
    focal_length_px = config.STEREO_FOCAL_LENGTH_PX
    for i, det in enumerate(detections):
        x1, y1, x2, y2 = det["bbox"]
        class_name = det["class"]
        conf = det["conf"]
        color = CLASS_COLORS.get(class_name, (255, 255, 255))

        cv2.rectangle(result, (x1, y1), (x2, y2), color, 2)

        label = f"{class_name} {conf:.2f}"

        if not disparity_available:
            label += f" | {config.NO_DISPARITY_LABEL}"
        elif distances is not None and i < len(distances):
            dist = distances[i]
            if dist is not None and config.DISTANCE_VALID_MIN_CM <= dist <= config.DISTANCE_VALID_MAX_CM:
                if dist < 100.0:
                    label += f" | {dist:.1f}cm"
                else:
                    label += f" | {dist/100:.2f}m"
            else:
                label += f" | {config.DISTANCE_INVALID_LABEL}"

        (tw, th), baseline = cv2.getTextSize(
            label, cv2.FONT_HERSHEY_SIMPLEX, 0.5, 2
        )
        cv2.rectangle(
            result,
            (x1, y1 - th - baseline - 4),
            (x1 + tw, y1),
            color,
            -1,
        )
        cv2.putText(
            result,
            label,
            (x1, y1 - baseline - 2),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 0, 0),
            2,
        )

    return result


def compute_bbox_disparity(disparity_map, bbox, center_ratio=0.5):
    x1, y1, x2, y2 = bbox
    margin_x = int((x2 - x1) * (1.0 - center_ratio) / 2)
    margin_y = int((y2 - y1) * (1.0 - center_ratio) / 2)
    cx1 = x1 + margin_x
    cy1 = y1 + margin_y
    cx2 = x2 - margin_x
    cy2 = y2 - margin_y
    if cx2 <= cx1 or cy2 <= cy1:
        cx1, cy1, cx2, cy2 = x1, y1, x2, y2
    roi = disparity_map[cy1:cy2, cx1:cx2]
    valid = roi[roi >= 0]
    if len(valid) == 0:
        return None
    return float(np.bincount(valid.astype(np.int64)).argmax())


def disparity_to_distance(disparity, baseline_cm, focal_length_px):
    if disparity is None or disparity <= 0:
        return None
    return (baseline_cm * focal_length_px) / disparity


def compute_bbox_distances(disparity_map, detections):
    if disparity_map is None:
        return [None] * len(detections)
    baseline = config.STEREO_PARAMS["BASELINE_CM"]
    focal = config.STEREO_FOCAL_LENGTH_PX
    distances = []
    for det in detections:
        disp = compute_bbox_disparity(disparity_map, det["bbox"])
        dist = disparity_to_distance(disp, baseline, focal)
        distances.append(dist)
    return distances


def crop_sgm_disparity(frame):
    h_off = config.SGM_DISP_PARAMS["H_OFST"]
    v_off = config.SGM_DISP_PARAMS["V_OFST"]
    width = config.SGM_DISP_PARAMS["WIDTH"]
    height = config.SGM_DISP_PARAMS["HEIGHT"]
    if frame is None:
        return None
    return frame[v_off:v_off + height, h_off:h_off + width]


def restore_disparity_map(disp_img):
    scale = config.SGM_DISP_PARAMS["SCALE_FACTOR"]
    max_disp = config.SGM_DISP_PARAMS["MAX_DISPARITY"]
    r_thresh = config.SGM_DISP_PARAMS["INVALID_R_THRESH"]
    g_thresh = config.SGM_DISP_PARAMS["INVALID_G_THRESH"]
    b_thresh = config.SGM_DISP_PARAMS["INVALID_B_THRESH"]
    subpixel_div = config.SGM_DISP_PARAMS.get("SUBPIXEL_DIVISOR", 2.0)

    if disp_img is None:
        return None

    b, g, r = cv2.split(disp_img)
    r = r.astype(np.float32)
    g = g.astype(np.float32)
    b = b.astype(np.float32)

    is_invalid = (r >= r_thresh) & (g <= g_thresh) & (b <= b_thresh)

    mean_val = (r + g + b) / 3.0

    byte_val = mean_val / scale
    disparity = byte_val / subpixel_div

    disparity[is_invalid] = -1.0

    return disparity


def visualize_disparity(disparity_map):
    if disparity_map is None:
        return None

    disp_norm = disparity_map.astype(np.float32)
    valid_mask = disp_norm >= 0
    max_val = config.SGM_DISP_PARAMS["MAX_DISPARITY"]

    disp_vis = np.zeros((disparity_map.shape[0], disparity_map.shape[1], 3), dtype=np.uint8)
    disp_vis[:] = (30, 30, 30)

    if np.any(valid_mask):
        valid_disp = (1.0 - disp_norm[valid_mask] / max_val) * 255.0
        valid_disp = valid_disp.astype(np.uint8)

        colored = cv2.applyColorMap(valid_disp, cv2.COLORMAP_JET)

        disp_vis[valid_mask] = colored.reshape(-1, 3)

    invalid_mask = ~valid_mask
    if np.any(invalid_mask):
        disp_vis[invalid_mask] = (0, 0, 200)

    return disp_vis


def get_disparity_stats(disparity_map):
    if disparity_map is None:
        return {}

    total = disparity_map.size
    valid_mask = disparity_map >= 0
    valid_count = np.sum(valid_mask)
    invalid_count = total - valid_count

    stats = {
        "total_pixels": total,
        "valid_pixels": int(valid_count),
        "invalid_pixels": int(invalid_count),
        "valid_ratio": float(valid_count / total * 100) if total > 0 else 0.0,
    }

    if valid_count > 0:
        valid_vals = disparity_map[valid_mask]
        stats["min_disp"] = float(np.min(valid_vals))
        stats["max_disp"] = float(np.max(valid_vals))
        stats["mean_disp"] = float(np.mean(valid_vals))
        stats["median_disp"] = float(np.median(valid_vals))

    return stats


def gpu_subpixel_fill_disparity(disparity_map, max_iter=30):
    device = _ensure_gpu()

    disp = torch.from_numpy(disparity_map.astype(np.float32)).to(device)
    valid = (disp >= 0).float()

    kernel_size = 5
    k = kernel_size // 2
    weights_np = np.array([
        [0.0, 0.0, 1.0, 0.0, 0.0],
        [0.0, 2.0, 3.0, 2.0, 0.0],
        [1.0, 3.0, 0.0, 3.0, 1.0],
        [0.0, 2.0, 3.0, 2.0, 0.0],
        [0.0, 0.0, 1.0, 0.0, 0.0],
    ], dtype=np.float32)
    weights_np = weights_np / weights_np.sum()
    weights = torch.from_numpy(weights_np).to(device).view(1, 1, kernel_size, kernel_size)

    h, w = disp.shape
    for _ in range(max_iter):
        disp_pad = disp.unsqueeze(0).unsqueeze(0)
        valid_pad = valid.unsqueeze(0).unsqueeze(0)

        weighted_sum = F.conv2d(disp_pad * valid_pad, weights, padding=k).view(h, w)
        weight_sum = F.conv2d(valid_pad, weights, padding=k).view(h, w)

        fill_region = (valid < 0.5) & (weight_sum > 0.01)

        if not fill_region.any():
            break

        disp[fill_region] = (weighted_sum / weight_sum.clamp(min=1e-6))[fill_region]
        valid[fill_region] = 1.0

    return disp.cpu().numpy()


def gpu_median_filter_disparity(disparity_map, kernel_size=5):
    device = _ensure_gpu()

    disp = torch.from_numpy(disparity_map.astype(np.float32)).to(device)
    pad = kernel_size // 2

    patches = F.unfold(disp.unsqueeze(0).unsqueeze(0), kernel_size=kernel_size, padding=pad)
    median_vals = patches.median(dim=1, keepdim=False).values
    result = median_vals.view(disp.shape)

    return result.cpu().numpy()


def gpu_visualize_disparity(disparity_map, max_disp=None):
    device = _ensure_gpu()

    if max_disp is None:
        max_disp = config.SGM_DISP_PARAMS["MAX_DISPARITY"]

    jet_table = _get_jet_table(device)
    disp = torch.from_numpy(disparity_map.astype(np.float32)).to(device)
    valid = disp >= 0
    h, w = disp.shape

    vis = torch.zeros((h, w, 3), dtype=torch.uint8, device=device)
    bg = torch.tensor([30, 30, 30], dtype=torch.uint8, device=device)
    vis[~valid] = bg

    if valid.any():
        norm = ((1.0 - disp[valid] / max_disp) * 255.0).long().clamp(0, 255)
        colors = jet_table.index_select(0, norm).byte()
        vis[valid] = colors

    return vis.cpu().numpy()


def calibrate_focal_from_disparity(disparity, real_distance_cm, baseline_cm=None):
    if baseline_cm is None:
        baseline_cm = config.STEREO_PARAMS["BASELINE_CM"]
    if disparity is None or disparity <= 0 or real_distance_cm is None or real_distance_cm <= 0:
        return None
    return (disparity * real_distance_cm) / baseline_cm


def gpu_process_disparity_pipeline(disparity_map, median_kernel=5, fill_max_iter=30):
    if disparity_map is None:
        return None, None

    filled = gpu_subpixel_fill_disparity(disparity_map, max_iter=fill_max_iter)

    filtered = gpu_median_filter_disparity(filled, kernel_size=median_kernel)

    vis = gpu_visualize_disparity(filtered)

    return filtered, vis


def disparity_to_pointcloud_gpu(disparity_map, baseline_cm=None, focal_px=None,
                                 cx=None, cy=None, z_min=None, z_max=None,
                                 color_map=None):
    if disparity_map is None:
        return None

    if baseline_cm is None:
        baseline_cm = config.STEREO_PARAMS["BASELINE_CM"]
    if focal_px is None:
        focal_px = config.STEREO_FOCAL_LENGTH_PX
    if cx is None:
        cx = config.PCD_PARAMS["CAM_CX"]
    if cy is None:
        cy = config.PCD_PARAMS["CAM_CY"]
    if z_min is None:
        z_min = config.PCD_PARAMS["Z_MIN_CM"]
    if z_max is None:
        z_max = config.PCD_PARAMS["Z_MAX_CM"]

    device = _ensure_gpu()
    disp = torch.from_numpy(disparity_map.astype(np.float32)).to(device)
    h, w = disp.shape

    valid = (disp >= 0.5) & (disp <= config.SGM_DISP_PARAMS["MAX_DISPARITY"])
    if not valid.any():
        return None

    z_map = torch.full_like(disp, -1.0)
    z_map[valid] = (baseline_cm * focal_px) / disp[valid].clamp(min=0.5)

    range_valid = (z_map >= z_min) & (z_map <= z_max)
    final_valid = valid & range_valid

    if not final_valid.any():
        return None

    v_idx, u_idx = torch.where(final_valid)
    z_vals = z_map[final_valid]
    x_vals = (u_idx.float() - cx) * z_vals / focal_px
    y_vals = (v_idx.float() - cy) * z_vals / focal_px

    if color_map is not None and color_map.shape[0] == h and color_map.shape[1] == w:
        cmap_t = torch.from_numpy(color_map.astype(np.float32)).to(device)
        colors = cmap_t[final_valid]
    else:
        z_norm = (z_vals - z_min) / (z_max - z_min)
        z_norm = z_norm.clamp(0.0, 1.0)

        z_idx = (z_norm * 255.0).long().clamp(0, 255)
        jet_table = _get_jet_table(device)
        colors = jet_table.index_select(0, z_idx)

    n = final_valid.sum().item()
    pts = torch.zeros((n, 6), dtype=torch.float32, device=device)
    pts[:, 0] = x_vals
    pts[:, 1] = y_vals
    pts[:, 2] = z_vals
    pts[:, 3:] = colors

    return pts.cpu().numpy()


def voxel_downsample_pointcloud(points, voxel_size_cm=1.0):
    if points is None or len(points) == 0:
        return None

    xyz = points[:, :3]
    rgb = points[:, 3:6]

    voxel_indices = np.floor(xyz / voxel_size_cm).astype(np.int32)

    voxel_dict = {}
    for i in range(len(points)):
        key = (voxel_indices[i, 0], voxel_indices[i, 1], voxel_indices[i, 2])
        if key not in voxel_dict:
            voxel_dict[key] = []
        voxel_dict[key].append(i)

    n_voxels = len(voxel_dict)
    downsampled = np.zeros((n_voxels, 6), dtype=np.float32)

    for idx, (key, pt_indices) in enumerate(voxel_dict.items()):
        indices_arr = np.array(pt_indices)
        downsampled[idx, :3] = np.mean(xyz[indices_arr], axis=0)
        downsampled[idx, 3:6] = np.mean(rgb[indices_arr], axis=0)

    return downsampled


def generate_pointcloud_from_disparity(disparity_map, voxel_size_cm=None,
                                        max_points=None):
    if disparity_map is None:
        return None

    if voxel_size_cm is None:
        voxel_size_px = config.PCD_PARAMS["VOXEL_SIZE_PX"]
        focal_px = config.STEREO_FOCAL_LENGTH_PX
        baseline_cm = config.STEREO_PARAMS["BASELINE_CM"]
        mid_z = 100.0
        voxel_size_cm = voxel_size_px * mid_z / focal_px

    if max_points is None:
        max_points = config.PCD_PARAMS["MAX_POINTS"]

    points = disparity_to_pointcloud_gpu(disparity_map)

    if points is None or len(points) == 0:
        return None

    if config.PCD_PARAMS["DOWNSAMPLE_ENABLED"] and len(points) > 1:
        points = voxel_downsample_pointcloud(points, voxel_size_cm)

    if points is not None and len(points) > max_points:
        indices = np.random.choice(len(points), max_points, replace=False)
        points = points[indices]

    return points


def compute_roi_disparity_stats(disparity_map, x1, y1, x2, y2):
    if disparity_map is None:
        return None

    h, w = disparity_map.shape
    x1 = max(0, min(x1, w - 1))
    x2 = max(x1 + 1, min(x2, w))
    y1 = max(0, min(y1, h - 1))
    y2 = max(y1 + 1, min(y2, h))

    roi = disparity_map[y1:y2, x1:x2]
    valid = roi[roi >= 0]

    if len(valid) == 0:
        return None

    return {
        "mean_disp": float(np.mean(valid)),
        "var_disp": float(np.var(valid)),
        "std_disp": float(np.std(valid)),
        "min_disp": float(np.min(valid)),
        "max_disp": float(np.max(valid)),
        "valid_count": int(len(valid)),
        "total_count": int(roi.size),
        "valid_ratio": float(len(valid) / roi.size * 100),
        "roi": (x1, y1, x2, y2),
    }


def draw_roi_measure_overlay(frame, roi, stats, distance_cm=None):
    if frame is None or roi is None:
        return frame if frame is not None else None

    result = frame.copy()
    x1, y1, x2, y2 = roi

    cv2.rectangle(result, (x1, y1), (x2, y2), (0, 255, 0), 2)

    if stats is None:
        return result

    lines = []
    lines.append(f"Disp Mean: {stats['mean_disp']:.2f}")
    lines.append(f"Disp Var: {stats['var_disp']:.2f}")
    lines.append(f"Disp Std: {stats['std_disp']:.2f}")
    lines.append(f"Range: [{stats['min_disp']:.1f}, {stats['max_disp']:.1f}]")
    lines.append(f"Valid: {stats['valid_count']}/{stats['total_count']} ({stats['valid_ratio']:.1f}%)")

    if distance_cm is not None:
        if distance_cm < 100.0:
            lines.append(f"Distance: {distance_cm:.1f} cm")
        else:
            lines.append(f"Distance: {distance_cm / 100:.2f} m")

    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.45
    thickness = 2
    line_height = 18

    label_x = x1
    label_y = y1 - 6

    for i, line in enumerate(lines):
        y_pos = label_y - i * line_height
        if y_pos < 10:
            y_pos = y2 + 6 + (i - (len(lines) - 1)) * line_height

        (tw, th), baseline = cv2.getTextSize(line, font, font_scale, thickness)
        cv2.rectangle(
            result,
            (label_x, y_pos - th - baseline),
            (label_x + tw, y_pos + baseline),
            (0, 0, 0),
            -1,
        )
        cv2.rectangle(
            result,
            (label_x, y_pos - th - baseline),
            (label_x + tw, y_pos + baseline),
            (0, 255, 0),
            1,
        )
        cv2.putText(
            result, line,
            (label_x, y_pos),
            font, font_scale, (0, 255, 0),
            thickness,
        )

    return result
