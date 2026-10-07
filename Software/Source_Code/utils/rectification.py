import os
import numpy as np
import cv2


WIDTH = 640
HEIGHT = 480
Q_SCALE = 8
Q_BITS = 3

_lut_left = None
_lut_right = None
_lut_loaded = False


def load_lut(lut_dir=None):
    global _lut_left, _lut_right, _lut_loaded

    if lut_dir is None:
        lut_dir = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            "..", "..", "Matlab", "calibration"
        )
        lut_dir = os.path.normpath(lut_dir)

    left_path = os.path.join(lut_dir, "rectification_lut_left.raw")
    right_path = os.path.join(lut_dir, "rectification_lut_right.raw")

    if not os.path.exists(left_path) or not os.path.exists(right_path):
        raise FileNotFoundError(
            f"LUT files not found:\n  {left_path}\n  {right_path}\n"
            f"Please run stereo_calibration.m first to generate them."
        )

    raw_left = np.fromfile(left_path, dtype=np.int8)
    raw_right = np.fromfile(right_path, dtype=np.int8)

    expected_size = WIDTH * HEIGHT * 2
    if raw_left.size != expected_size:
        raise ValueError(
            f"Left LUT size mismatch: got {raw_left.size} bytes, expected {expected_size}"
        )
    if raw_right.size != expected_size:
        raise ValueError(
            f"Right LUT size mismatch: got {raw_right.size} bytes, expected {expected_size}"
        )

    dx_l = raw_left[0::2].reshape(HEIGHT, WIDTH).astype(np.float32) / Q_SCALE
    dy_l = raw_left[1::2].reshape(HEIGHT, WIDTH).astype(np.float32) / Q_SCALE
    dx_r = raw_right[0::2].reshape(HEIGHT, WIDTH).astype(np.float32) / Q_SCALE
    dy_r = raw_right[1::2].reshape(HEIGHT, WIDTH).astype(np.float32) / Q_SCALE

    _lut_left = (dx_l, dy_l)
    _lut_right = (dx_r, dy_r)
    _lut_loaded = True

    return True


def is_loaded():
    return _lut_loaded


def _apply_lut(img, dx_map, dy_map):
    yy, xx = np.mgrid[0:HEIGHT, 0:WIDTH]
    src_x = xx + dx_map
    src_y = yy + dy_map

    valid = (src_x >= 0) & (src_x < WIDTH - 1) & (src_y >= 0) & (src_y < HEIGHT - 1)
    result = np.zeros((HEIGHT, WIDTH), dtype=np.uint8)

    src_x_clip = np.clip(src_x[valid], 0, WIDTH - 1.001)
    src_y_clip = np.clip(src_y[valid], 0, HEIGHT - 1.001)

    x0 = np.floor(src_x_clip).astype(np.int32)
    y0 = np.floor(src_y_clip).astype(np.int32)
    x1 = np.minimum(x0 + 1, WIDTH - 1)
    y1 = np.minimum(y0 + 1, HEIGHT - 1)

    wx = src_x_clip - x0
    wy = src_y_clip - y0

    if img.ndim == 2:
        source = img
        result[valid] = (
            (1 - wx) * (1 - wy) * source[y0, x0]
            + wx * (1 - wy) * source[y0, x1]
            + (1 - wx) * wy * source[y1, x0]
            + wx * wy * source[y1, x1]
        ).astype(np.uint8)
    else:
        source = img
        for c in range(img.shape[2]):
            result_c = (
                (1 - wx) * (1 - wy) * source[y0, x0, c]
                + wx * (1 - wy) * source[y0, x1, c]
                + (1 - wx) * wy * source[y1, x0, c]
                + wx * wy * source[y1, x1, c]
            )
            if c == 0:
                result = np.zeros((HEIGHT, WIDTH, img.shape[2]), dtype=np.uint8)
            result[valid, c] = result_c.astype(np.uint8)[valid]

    return result


def rectify_left(img_bgr):
    if not _lut_loaded:
        raise RuntimeError("LUT not loaded. Call load_lut() first.")
    result = np.zeros_like(img_bgr)
    for c in range(3):
        result[:, :, c] = _apply_lut(img_bgr[:, :, c], _lut_left[0], _lut_left[1])
    return result


def rectify_right(img_bgr):
    if not _lut_loaded:
        raise RuntimeError("LUT not loaded. Call load_lut() first.")
    result = np.zeros_like(img_bgr)
    for c in range(3):
        result[:, :, c] = _apply_lut(img_bgr[:, :, c], _lut_right[0], _lut_right[1])
    return result


def rectify_left_gray(img_gray):
    if not _lut_loaded:
        raise RuntimeError("LUT not loaded. Call load_lut() first.")
    return _apply_lut(img_gray, _lut_left[0], _lut_left[1])


def rectify_right_gray(img_gray):
    if not _lut_loaded:
        raise RuntimeError("LUT not loaded. Call load_lut() first.")
    return _apply_lut(img_gray, _lut_right[0], _lut_right[1])
