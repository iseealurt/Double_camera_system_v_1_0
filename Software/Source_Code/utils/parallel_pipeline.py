import time
import threading
import traceback
import queue as queue_module

from utils.timestamp_buffer import TimestampBuffer
from utils.image_processor import (
    crop_left_camera,
    crop_right_camera,
    crop_sgm_disparity,
    restore_disparity_map,
    gpu_process_disparity_pipeline,
    compute_bbox_distances,
)
from utils.distance_tracker import DistanceTracker
from utils import config

try:
    import torch
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False


class ParallelPipeline:
    def __init__(self, defect_detector, board_detector, pnp_processor=None,
                 heatmap_active=False, pcd_active=False):
        self._ts_buffer = TimestampBuffer(max_age_sec=0.5, max_size=20)
        self._defect_detector = defect_detector
        self._board_detector = board_detector
        self._pnp_processor = pnp_processor
        self._heatmap_active = heatmap_active
        self._pcd_active = pcd_active

        self._input_queue = queue_module.Queue(maxsize=4)
        self._running = False
        self._gpu_thread = None

        self._state_lock = threading.Lock()
        self._frame_counter = 0
        self._board_counter = 0

        self._disp_map = None
        self._board_detection = None
        self._board_distance = None
        self._defect_detections = []
        self._last_distances = []
        self._dist_tracker = DistanceTracker()
        self._pnp_pose_result = None
        self._pnp_similarity = 0.0
        self._pnp_frame_counter = 0

        self._has_error = False
        self._last_error_msg = ""

        self._cuda_ready = False
        self._drop_count = 0
        self._start_gpu_thread()

    def _start_gpu_thread(self):
        self._running = True
        if HAS_TORCH and torch.cuda.is_available():
            torch.cuda.init()
            _ = torch.zeros(1, device='cuda')
            import utils.image_processor as ip_module
            ip_module._ensure_gpu()
            self._cuda_ready = True
        self._gpu_thread = threading.Thread(target=self._gpu_loop, daemon=True, name="GPU-Worker")
        self._gpu_thread.start()

    def _gpu_loop(self):
        while self._running:
            try:
                task = self._input_queue.get(timeout=0.1)
            except queue_module.Empty:
                continue

            try:
                ts = task['ts']

                if task.get('disp_crop') is not None:
                    self._process_disparity(ts, task['disp_crop'])

                if task.get('do_board') and self._board_detector is not None and self._board_detector.is_loaded:
                    self._process_board(ts, task['left_crop'])

                if task.get('do_defect') and self._defect_detector is not None:
                    self._process_defect(ts, task['left_crop'])

            except Exception:
                traceback.print_exc()
                self._has_error = True
                self._last_error_msg = traceback.format_exc()

    def _process_disparity(self, ts, disp_crop):
        disp_map = restore_disparity_map(disp_crop)
        if disp_map is not None:
            disp_map, disp_vis = gpu_process_disparity_pipeline(
                disp_map, median_kernel=5, fill_max_iter=30
            )
            self._disp_map = disp_map
            self._ts_buffer.put_disp(ts, disp_map, disp_vis)

    def _process_board(self, ts, left_crop):
        det = self._board_detector.detect_best(left_crop)
        self._board_detection = det
        if det is not None and self._disp_map is not None:
            dists = compute_bbox_distances(self._disp_map, [{'bbox': det['bbox']}])
            self._board_distance = dists[0] if dists else None
        else:
            self._board_distance = None
        self._ts_buffer.put_board(ts, det)

    def _process_defect(self, ts, left_crop):
        dets = self._defect_detector.detect(
            left_crop,
            conf_threshold=config.MODEL_CONF_THRESHOLD,
            iou_threshold=config.MODEL_IOU_THRESHOLD,
        )
        if dets:
            self._defect_detections = dets
            if self._disp_map is not None:
                raw_dists = compute_bbox_distances(self._disp_map, dets)
                self._last_distances = self._dist_tracker.update(dets, raw_dists)
            else:
                self._last_distances = []
        else:
            self._defect_detections = []
            self._last_distances = []
        self._ts_buffer.put_defect(ts, dets if dets else [])

    def submit_frame(self, frame):
        ts = time.perf_counter()
        self._frame_counter += 1

        left_crop = crop_left_camera(frame)
        right_crop = crop_right_camera(frame)

        if left_crop is None:
            return ts, None, None

        self._ts_buffer.put_frame_meta(
            ts, left_crop.copy(),
            right_crop.copy() if right_crop is not None else None
        )

        task = {
            'ts': ts,
            'left_crop': left_crop.copy(),
            'disp_crop': None,
            'do_board': False,
            'do_defect': False,
        }

        if self._heatmap_active or self._pcd_active:
            disp_crop = crop_sgm_disparity(frame)
            if disp_crop is not None:
                task['disp_crop'] = disp_crop.copy()

        if self._board_detector is not None and self._board_detector.is_loaded:
            self._board_counter += 1
            task['do_board'] = (self._board_counter % config.PCB_BOARD_PNP_TRIGGER_INTERVAL == 0)

        if self._defect_detector is not None:
            task['do_defect'] = True

        try:
            self._input_queue.put_nowait(task)
        except queue_module.Full:
            pass

        return ts, left_crop, right_crop

    def get_merged(self):
        return self._ts_buffer.get_merged()

    def update_pnp(self, left_crop, board_det=None):
        if self._pnp_processor is None or not self._pnp_processor.template_loaded:
            return

        if board_det is None:
            self._pnp_pose_result = None
            return

        self._pnp_frame_counter += 1
        try:
            match_result = self._pnp_processor.yolo_match(left_crop, board_det)
            if match_result is not None:
                self._pnp_similarity = match_result["similarity"]
                self._pnp_pose_result = self._pnp_processor.estimate_pose(match_result["corners"])
            else:
                self._pnp_similarity = 0.0
                self._pnp_pose_result = None
        except Exception:
            traceback.print_exc()
            self._pnp_similarity = 0.0
            self._pnp_pose_result = None

    def shutdown(self):
        self._running = False
        if self._gpu_thread is not None and self._gpu_thread.is_alive():
            self._gpu_thread.join(timeout=2.0)
        self._gpu_thread = None

    def reset(self):
        self._ts_buffer.reset()
        with self._state_lock:
            self._disp_map = None
            self._board_detection = None
            self._board_distance = None
            self._defect_detections = []
            self._last_distances = []
            self._has_error = False
            self._last_error_msg = ""
        self._pnp_pose_result = None
        self._pnp_similarity = 0.0

    @property
    def disp_map(self):
        return self._disp_map

    @property
    def board_detection(self):
        return self._board_detection

    @property
    def board_distance(self):
        return self._board_distance

    @property
    def defect_detections(self):
        return self._defect_detections

    @property
    def last_distances(self):
        return self._last_distances

    @property
    def pnp_pose_result(self):
        return self._pnp_pose_result

    @property
    def pnp_similarity(self):
        return self._pnp_similarity

    @property
    def has_error(self):
        return self._has_error

    @property
    def last_error(self):
        return self._last_error_msg

    def reset_error(self):
        with self._state_lock:
            self._has_error = False
            self._last_error_msg = ""
