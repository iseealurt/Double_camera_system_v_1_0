import threading
import time
from collections import deque


class TimestampBuffer:
    """Thread-safe buffer that stores parallel pipeline results keyed by timestamp.
    Provides closest-timestamp matching for downstream display merging."""

    def __init__(self, max_age_sec=0.5, max_size=20):
        self._lock = threading.Lock()
        self._max_age = max_age_sec
        self._max_size = max_size
        self._disp_buf = deque()
        self._board_buf = deque()
        self._defect_buf = deque()
        self._frame_meta_buf = deque()

    def put_disp(self, ts, disp_map, disp_vis):
        """Store disparity pipeline result with timestamp."""
        with self._lock:
            self._disp_buf.append((ts, disp_map, disp_vis))
            self._trim(self._disp_buf)
            self._prune_expired(self._disp_buf)

    def put_board(self, ts, detection):
        """Store PCB board detection result with timestamp."""
        with self._lock:
            self._board_buf.append((ts, detection))
            self._trim(self._board_buf)
            self._prune_expired(self._board_buf)

    def put_defect(self, ts, detections):
        """Store defect detection results with timestamp."""
        with self._lock:
            self._defect_buf.append((ts, detections))
            self._trim(self._defect_buf)
            self._prune_expired(self._defect_buf)

    def put_frame_meta(self, ts, left_crop, right_crop):
        """Store frame crops for display with timestamp."""
        with self._lock:
            self._frame_meta_buf.append((ts, left_crop, right_crop))
            self._trim(self._frame_meta_buf)
            self._prune_expired(self._frame_meta_buf)

    def get_merged(self):
        """Returns dict with results for the latest frame.
        Uses the newest frame_meta as display frame,
        matches disparity/board/defect results by closest timestamp."""
        with self._lock:
            if not self._frame_meta_buf:
                return None

            target_ts, left_crop, right_crop = self._frame_meta_buf[-1]

            disp_entry = self._closest(self._disp_buf, target_ts)
            board_entry = self._closest(self._board_buf, target_ts)
            defect_entry = self._closest(self._defect_buf, target_ts)

            result = {
                'timestamp': target_ts,
                'left_crop': left_crop,
                'right_crop': right_crop,
                'disp_map': disp_entry[1] if disp_entry is not None else None,
                'disp_vis': disp_entry[2] if disp_entry is not None else None,
                'board_detection': board_entry[1] if board_entry is not None else None,
                'defect_detections': defect_entry[1] if defect_entry is not None else [],
            }

            self._cleanup_all()
            return result

    def reset(self):
        """Clear all buffers."""
        with self._lock:
            self._disp_buf.clear()
            self._board_buf.clear()
            self._defect_buf.clear()
            self._frame_meta_buf.clear()

    def _closest(self, buf, target_ts):
        """Find entry with minimum abs(ts - target_ts). Returns (ts, ...) tuple or None."""
        if not buf:
            return None
        best = None
        best_diff = float('inf')
        for entry in buf:
            diff = abs(entry[0] - target_ts)
            if diff < best_diff:
                best_diff = diff
                best = entry
        return best

    def _exact_match(self, buf, target_ts):
        """Find entry with exact timestamp match. Returns (ts, ...) tuple or None."""
        for entry in buf:
            if entry[0] == target_ts:
                return entry
        return None

    def _trim(self, buf):
        """Removes oldest entries if len > max_size."""
        while len(buf) > self._max_size:
            buf.popleft()

    def _prune_expired(self, buf):
        """Removes entries older than max_age_sec from now."""
        now = time.perf_counter()
        while buf and (now - buf[0][0]) > self._max_age:
            buf.popleft()

    def _cleanup_all(self):
        """Calls _prune_expired on all four buffers."""
        self._prune_expired(self._disp_buf)
        self._prune_expired(self._board_buf)
        self._prune_expired(self._defect_buf)
        self._prune_expired(self._frame_meta_buf)
