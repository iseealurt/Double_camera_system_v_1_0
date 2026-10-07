import numpy as np
import cv2


IMG_WIDTH = 640
IMG_HEIGHT = 480
MAX_DISPARITY = 48
CENSUS_WIDTH = 24
CENSUS_WIN = 5
CENSUS_HALF = 2
SGM_P1 = 3
SGM_P2 = 24
SGM_INVALID_COST = 24
CONFIDENCE_THRE = 1
SUBPIXEL_DIVISOR = 2.0


def compute_census_5x5(gray_img):
    h, w = gray_img.shape
    census = np.zeros((h, w), dtype=np.uint32)

    for dy in range(-CENSUS_HALF, CENSUS_HALF + 1):
        for dx in range(-CENSUS_HALF, CENSUS_HALF + 1):
            if dy == 0 and dx == 0:
                continue
            bit_idx = (dy + CENSUS_HALF) * CENSUS_WIN + (dx + CENSUS_HALF)
            if dy < 0 and dx < 0:
                bit_idx -= 1
            if dy < 0 and dx >= 0:
                bit_idx -= 1
            if dy == 0 and dx > 0:
                bit_idx -= 1

            shifted = np.zeros_like(gray_img, dtype=np.uint8)
            if dy < 0:
                shifted[-dy:, :] = gray_img[:h+dy, :]
            elif dy > 0:
                shifted[:h-dy, :] = gray_img[dy:, :]
            else:
                shifted = gray_img

            if dx < 0:
                shifted_xy = np.zeros_like(gray_img, dtype=np.uint8)
                shifted_xy[:, -dx:] = shifted[:, :w+dx]
                shifted = shifted_xy
            elif dx > 0:
                shifted_xy = np.zeros_like(gray_img, dtype=np.uint8)
                shifted_xy[:, :w-dx] = shifted[:, dx:]
                shifted = shifted_xy

            gt = (shifted > gray_img) & 1
            census |= (gt.astype(np.uint32) << bit_idx).astype(np.uint32)

    return census


def _popcount_24bit(arr):
    t0 = arr.astype(np.uint64)
    t0 = (t0 & 0x5555555555555555) + ((t0 >> 1) & 0x5555555555555555)
    t0 = (t0 & 0x3333333333333333) + ((t0 >> 2) & 0x3333333333333333)
    t0 = (t0 & 0x0F0F0F0F0F0F0F0F) + ((t0 >> 4) & 0x0F0F0F0F0F0F0F0F)
    t0 = (t0 & 0x00FF00FF00FF00FF) + ((t0 >> 8) & 0x00FF00FF00FF00FF)
    t0 = (t0 & 0x0000FFFF0000FFFF) + ((t0 >> 16) & 0x0000FFFF0000FFFF)
    t0 = (t0 & 0x00000000FFFFFFFF) + ((t0 >> 32) & 0x00000000FFFFFFFF)
    return t0.astype(np.uint8)


def sgm_2dir(census_left, census_right):
    h, w = census_left.shape

    cost_volume = np.full((h, w, MAX_DISPARITY), SGM_INVALID_COST, dtype=np.uint8)

    for d in range(MAX_DISPARITY):
        right_shifted = np.zeros_like(census_right, dtype=np.uint32)
        if d > 0:
            right_shifted[:, d:] = census_right[:, :w-d]

        xor_result = (census_left ^ right_shifted).astype(np.uint64)
        ham_dist = _popcount_24bit(xor_result)

        valid_mask = np.zeros((h, w), dtype=bool)
        valid_mask[:, d:] = True
        cost_volume[:, :, d][valid_mask] = ham_dist[valid_mask]

    cost_volume_i32 = cost_volume.astype(np.int32)

    L1 = np.full((h, w, MAX_DISPARITY), 0, dtype=np.int32)

    for y in range(h):
        L1_prev = np.zeros(MAX_DISPARITY, dtype=np.int32)
        for x in range(w):
            prev_min = np.min(L1_prev)
            for d in range(MAX_DISPARITY):
                cost_d = cost_volume_i32[y, x, d]

                candidates = [L1_prev[d] + cost_d]

                if d > 0:
                    candidates.append(L1_prev[d - 1] + SGM_P1 + cost_d)
                if d < MAX_DISPARITY - 1:
                    candidates.append(L1_prev[d + 1] + SGM_P1 + cost_d)

                candidates.append(prev_min + SGM_P2 + cost_d)

                L1[y, x, d] = min(candidates)

            L1_prev = L1[y, x, :]

    L3 = np.full((h, w, MAX_DISPARITY), 0, dtype=np.int32)

    for y in range(h):
        L3_prev = np.zeros(MAX_DISPARITY, dtype=np.int32)
        for x in range(w - 1, -1, -1):
            prev_min = np.min(L3_prev)
            for d in range(MAX_DISPARITY):
                cost_d = cost_volume_i32[y, x, d]

                candidates = [L3_prev[d] + cost_d]

                if d > 0:
                    candidates.append(L3_prev[d - 1] + SGM_P1 + cost_d)
                if d < MAX_DISPARITY - 1:
                    candidates.append(L3_prev[d + 1] + SGM_P1 + cost_d)

                candidates.append(prev_min + SGM_P2 + cost_d)

                L3[y, x, d] = min(candidates)

            L3_prev = L3[y, x, :]

    L_sum = L1 + L3

    disparity_map = np.zeros((h, w), dtype=np.int32)
    second_min_map = np.zeros((h, w), dtype=np.int32)

    for y in range(h):
        for x in range(w):
            costs = L_sum[y, x, :]
            if x < MAX_DISPARITY - 1:
                sorted_idx = np.argsort(costs)
                best_d = sorted_idx[0]
                second_d = sorted_idx[1]
                disparity_map[y, x] = best_d
                second_min_map[y, x] = costs[second_d] - costs[best_d]
            else:
                disparity_map[y, x] = 0
                second_min_map[y, x] = 0

    subpixel_map = np.zeros((h, w), dtype=np.int32)
    for y in range(h):
        for x in range(w):
            d = disparity_map[y, x]
            if d == 0 or d >= MAX_DISPARITY - 1:
                subpixel_map[y, x] = 0
                continue

            cost_curr = L_sum[y, x, d]
            cost_plus = L_sum[y, x, d + 1]
            cost_minus = L_sum[y, x, d - 1]

            if cost_plus < cost_minus:
                bias = 1
            elif cost_minus < cost_plus:
                bias = -1
            else:
                bias = 0

            subpixel_map[y, x] = bias

    return disparity_map, subpixel_map, second_min_map


def encode_disparity(disparity_map, subpixel_map, confidence_map):
    h, w = disparity_map.shape
    encoded = np.zeros((h, w), dtype=np.uint8)

    valid = confidence_map >= CONFIDENCE_THRE

    best_disp = disparity_map.astype(np.int32)
    bias = subpixel_map.astype(np.int32)

    disp_val = np.zeros((h, w), dtype=np.int32)
    disp_val[valid] = best_disp[valid] * 2 + bias[valid]
    disp_val = np.clip(disp_val, 0, 127)

    encoded[valid] = disp_val[valid].astype(np.uint8)
    encoded[~valid] = 128

    return encoded


def compute_sgm_disparity(left_gray, right_gray):
    census_left = compute_census_5x5(left_gray)
    census_right = compute_census_5x5(right_gray)

    disparity_map, subpixel_map, confidence_map = sgm_2dir(census_left, census_right)

    encoded = encode_disparity(disparity_map, subpixel_map, confidence_map)

    float_disp = disparity_map.astype(np.float32) + subpixel_map.astype(np.float32) * 0.5
    float_disp[confidence_map < CONFIDENCE_THRE] = -1.0

    return encoded, float_disp, disparity_map, confidence_map


def compare_with_fpga(sw_encoded, fpga_disp_crop, disp_map_full):
    subpixel_div = 2.0
    r_thresh = 200
    g_thresh = 50
    b_thresh = 50

    if fpga_disp_crop is None:
        return None

    b, g, r = cv2.split(fpga_disp_crop)
    r_f = r.astype(np.float32)
    g_f = g.astype(np.float32)
    b_f = b.astype(np.float32)

    fpga_invalid = (r_f >= r_thresh) & (g_f <= g_thresh) & (b_f <= b_thresh)
    fpga_mean = (r_f + g_f + b_f) / 3.0
    fpga_disp_float = fpga_mean / subpixel_div
    fpga_disp_float[fpga_invalid] = -1.0

    sw_valid = disp_map_full >= 0
    fpga_valid = fpga_disp_float >= 0

    both_valid = sw_valid & fpga_valid
    num_both = np.sum(both_valid)

    if num_both > 0:
        diff = disp_map_full[both_valid] - fpga_disp_float[both_valid]
        rmse = np.sqrt(np.mean(diff ** 2))
        max_diff = np.max(np.abs(diff))
        mean_diff = np.mean(diff)
        mean_abs_diff = np.mean(np.abs(diff))
        corr = np.corrcoef(disp_map_full[both_valid], fpga_disp_float[both_valid])[0, 1]
    else:
        rmse = max_diff = mean_diff = mean_abs_diff = corr = 0.0

    diff_map = np.zeros(disp_map_full.shape, dtype=np.float32)
    diff_map[both_valid] = disp_map_full[both_valid] - fpga_disp_float[both_valid]
    diff_map[~both_valid] = 0.0

    return {
        "num_both_valid": int(num_both),
        "rmse": float(rmse),
        "max_diff": float(max_diff),
        "mean_diff": float(mean_diff),
        "mean_abs_diff": float(mean_abs_diff),
        "correlation": float(corr),
        "sw_valid_pct": float(np.sum(sw_valid) / disp_map_full.size * 100),
        "fpga_valid_pct": float(np.sum(fpga_valid) / fpga_disp_float.size * 100),
        "diff_map": diff_map,
        "fpga_disp": fpga_disp_float,
    }
