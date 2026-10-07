import time
from collections import deque


STAGE_LABELS = {
    'camera_read': 'Cam',
    'yolo_inference': 'YOLO',
    'disparity_pipeline': 'DISP',
    'distance_compute': 'DIST',
    'total_frame': 'Total',
    'pcb_board_detect': 'PCB',
    'pnp_pose': 'PnP',
}


class ProcessingLatencyTracker:
    def __init__(self, fps_window_sec=1.0, max_samples=60):
        self._fps_window_sec = fps_window_sec
        self._frame_timestamps = deque()
        self._stage_samples = {}
        self._stage_active = {}
        self._display_counter = 0

    def _ensure_stage(self, name):
        if name not in self._stage_samples:
            self._stage_samples[name] = deque(maxlen=60)

    def start_stage(self, name):
        self._ensure_stage(name)
        self._stage_active[name] = time.perf_counter()

    def end_stage(self, name):
        if name in self._stage_active:
            elapsed = time.perf_counter() - self._stage_active[name]
            self._ensure_stage(name)
            self._stage_samples[name].append(elapsed)
            del self._stage_active[name]

    def record_stage_latency(self, name, elapsed_sec):
        self._ensure_stage(name)
        self._stage_samples[name].append(elapsed_sec)

    def tick_frame(self):
        now = time.perf_counter()
        self._frame_timestamps.append(now)
        self._trim_old(now)

    def _trim_old(self, now):
        cutoff = now - self._fps_window_sec
        while self._frame_timestamps and self._frame_timestamps[0] < cutoff:
            self._frame_timestamps.popleft()

    def get_fps(self):
        if len(self._frame_timestamps) < 2:
            return 0.0
        elapsed = self._frame_timestamps[-1] - self._frame_timestamps[0]
        if elapsed <= 0:
            return 0.0
        return len(self._frame_timestamps) / elapsed

    def get_avg_latency_ms(self, name):
        samples = self._stage_samples.get(name)
        if not samples or len(samples) == 0:
            return None
        return (sum(samples) / len(samples)) * 1000

    def get_status_string(self, active_stages):
        parts = [f"FPS: {self.get_fps():.0f}"]

        for stage_key, stage_label in [
            ('yolo_inference', 'YOLO'),
            ('disparity_pipeline', 'DISP'),
            ('distance_compute', 'DIST'),
            ('pcb_board_detect', 'PCB'),
        ]:
            if stage_key in active_stages:
                avg = self.get_avg_latency_ms(stage_key)
                if avg is not None:
                    parts.append(f"{stage_label}: {avg:.0f}ms")

        total_avg = self.get_avg_latency_ms('total_frame')
        if total_avg is not None:
            parts.append(f"Total: {total_avg:.0f}ms")

        return " | ".join(parts)

    def should_update_display(self, interval=15):
        self._display_counter += 1
        if self._display_counter >= interval:
            self._display_counter = 0
            return True
        return False

    def reset(self):
        self._frame_timestamps.clear()
        self._stage_samples.clear()
        self._stage_active.clear()
        self._display_counter = 0
