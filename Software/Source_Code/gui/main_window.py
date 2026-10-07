import cv2
import time
import numpy as np
import threading
from enum import IntEnum
from PyQt5.QtWidgets import (
    QMainWindow,
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QPushButton,
    QComboBox,
    QLabel,
    QStatusBar,
    QGroupBox,
    QLineEdit,
    QStackedWidget,
    QAction,
    QActionGroup,
    QMenu,
    QPlainTextEdit,
)
from PyQt5.QtCore import QTimer, Qt, QThread, pyqtSignal, QObject, QDateTime
from PyQt5.QtGui import QTextCursor

from camera.capture import CameraCapture
from utils.image_processor import (
    crop_left_camera,
    crop_right_camera,
    draw_pcb_detections,
    draw_pcb_board_detection,
    crop_sgm_disparity,
    restore_disparity_map,
    visualize_disparity,
    get_disparity_stats,
    gpu_process_disparity_pipeline,
    gpu_visualize_disparity,
    compute_bbox_distances,
    compute_bbox_disparity,
    calibrate_focal_from_disparity,
    generate_pointcloud_from_disparity,
    compute_roi_disparity_stats,
    draw_roi_measure_overlay,
    disparity_to_distance,
)
from gui.image_viewer import ImageViewer
from gui.point_cloud_viewer import PointCloudViewer
from utils.pcb_detector import PCBDetector
from utils.pcb_board_detector import PCBBoardDetector
from utils.latency_tracker import ProcessingLatencyTracker
from utils.parallel_pipeline import ParallelPipeline
from utils import config
from utils.rectification import load_lut, rectify_left_gray, rectify_right_gray, is_loaded as rect_lut_loaded
from utils.sgm_debug import compute_sgm_disparity, encode_disparity, compare_with_fpga as sgm_compare


FRAME_INTERVAL_MS = 33


class AppState(IntEnum):
    IDLE = 0
    PREVIEW = 1
    CONNECTED = 2


class ViewMode(IntEnum):
    LEFT = 0
    RIGHT = 1
    DISPARITY = 2
    YOLO_LOG = 3
    DEBUG = 4


class CameraListWorker(QObject):
    finished = pyqtSignal(list)

    def run(self):
        try:
            available = CameraCapture.list_cameras()
            self.finished.emit(available)
        except Exception:
            self.finished.emit([])


class CameraOpenWorker(QObject):
    opened = pyqtSignal(object)
    failed = pyqtSignal(str)
    progress = pyqtSignal(str)

    def __init__(self, camera_id):
        super().__init__()
        self.camera_id = camera_id

    def run(self):
        cam = CameraCapture()
        try:
            self.progress.emit("Opening camera via DirectShow...")
            cam.open(self.camera_id)
            self.opened.emit(cam)
        except RuntimeError as e:
            self.failed.emit(str(e))


class MainWindow(QMainWindow):
    _sgm_debug_ready = pyqtSignal(object, str)

    def __init__(self):
        super().__init__()
        self.camera = CameraCapture()
        self.state = AppState.IDLE
        self._first_frame_received = False
        self._heatmap_active = False
        self._pcd_active = False
        self._disp_map = None
        self._last_pcd_update_time = 0.0
        self._pcd_update_interval = 1.0 / max(config.PCD_PARAMS["REFRESH_RATE_HZ"], 1)
        self._measure_mode = False
        self._measure_roi = None
        self._measure_stats = None
        self._measure_distance = None
        self.worker = None
        self.worker_thread = None
        self.list_worker_thread = None
        self.detector = None
        self.detections = []
        self._last_distances = []
        self._latency_tracker = ProcessingLatencyTracker()
        self._pipeline = None
        self._parallel_enabled = True
        self._sgm_debug_running = False
        self._view_mode = ViewMode.LEFT
        self._yolo_log_entries = []
        self._calib_mode = False
        self._calib_samples = []
        self._calib_disp_values = []
        self._calib_current_focal = config.STEREO_FOCAL_LENGTH_PX

        self.pnp_processor = None
        self.pnp_template_loaded = False
        self.pnp_pose_result = None
        self.pnp_similarity = 0.0
        self._pnp_frame_counter = 0

        self.pcb_board_detector = None
        self.pcb_board_detection = None
        self.pcb_board_distance = None
        self._pcb_board_frame_counter = 0

        self._debug_mode = False
        self._debug_lut_loaded = False
        self._debug_last_stats = None
        self._debug_sw_disp_map = None
        self._debug_fpga_disp_map = None
        self._debug_diff_map = None
        self._debug_frame_counter = 0

        self._setup_ui()
        self._setup_menu()
        self._setup_timer()
        self._sgm_debug_ready.connect(self._sgm_debug_show)
        QTimer.singleShot(0, self._refresh_camera_list_async)

    def _setup_ui(self):
        self.setWindowTitle(f"Dual Camera {config.CROP_HEIGHT}P Viewer")
        self.setMinimumSize(1400, 720)

        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)

        control_group = QGroupBox("Camera Control")
        control_layout = QHBoxLayout(control_group)

        self.camera_combo = QComboBox()
        self.camera_combo.setMinimumWidth(180)

        refresh_btn = QPushButton("Refresh")
        refresh_btn.clicked.connect(self._refresh_camera_list_async)

        manual_label = QLabel("Manual ID:")
        self.manual_input = QLineEdit()
        self.manual_input.setPlaceholderText("e.g. 0")
        self.manual_input.setMaximumWidth(80)

        self.preview_btn = QPushButton("Preview")
        self.preview_btn.clicked.connect(self._on_preview_clicked)

        self.connect_btn = QPushButton("Connect")
        self.connect_btn.clicked.connect(self._on_connect_clicked)

        self.disconnect_btn = QPushButton("Disconnect")
        self.disconnect_btn.clicked.connect(self._disconnect)

        self.heatmap_btn = QPushButton("Heatmap: OFF")
        self.heatmap_btn.setCheckable(True)
        self.heatmap_btn.toggled.connect(self._on_toggle_heatmap)

        self.pcd_btn = QPushButton("3D Point Cloud: OFF")
        self.pcd_btn.setCheckable(True)
        self.pcd_btn.toggled.connect(self._on_toggle_pcd)

        self.measure_btn = QPushButton("手动测距")
        self.measure_btn.setCheckable(True)
        self.measure_btn.toggled.connect(self._on_toggle_measure)
        self.measure_btn.setVisible(False)

        self.defect_btn = QPushButton("缺陷识别: OFF")
        self.defect_btn.setCheckable(True)
        self.defect_btn.toggled.connect(self._on_defect_toggle)

        self.pnp_btn = QPushButton("Add_PnP_template")
        self.pnp_btn.clicked.connect(self._on_add_pnp_template)

        self.debug_btn = QPushButton("SGM Debug: OFF")
        self.debug_btn.setCheckable(True)
        self.debug_btn.toggled.connect(self._on_toggle_debug)

        control_layout.addWidget(QLabel("Camera:"))
        control_layout.addWidget(self.camera_combo)
        control_layout.addWidget(refresh_btn)
        control_layout.addWidget(manual_label)
        control_layout.addWidget(self.manual_input)
        control_layout.addWidget(self.preview_btn)
        control_layout.addWidget(self.connect_btn)
        control_layout.addWidget(self.disconnect_btn)
        control_layout.addWidget(self.heatmap_btn)
        control_layout.addWidget(self.pcd_btn)
        control_layout.addWidget(self.measure_btn)
        control_layout.addWidget(self.defect_btn)
        control_layout.addWidget(self.pnp_btn)
        control_layout.addWidget(self.debug_btn)
        control_layout.addStretch()

        self.stacked = QStackedWidget()

        self.preview_viewer = ImageViewer("Select a camera and click Preview")
        self.stacked.addWidget(self.preview_viewer)

        self.connected_widget = QWidget()
        connected_layout = QVBoxLayout(self.connected_widget)
        connected_layout.setContentsMargins(0, 0, 0, 0)

        self.connected_stacked = QStackedWidget()

        self.left_viewer = ImageViewer("Left Camera - 480P")
        self.right_viewer = ImageViewer("Right Camera - 480P")

        self.disp_container = QWidget()
        disp_container_layout = QHBoxLayout(self.disp_container)
        disp_container_layout.setContentsMargins(0, 0, 0, 0)
        disp_container_layout.setSpacing(4)

        self.disp_heatmap_viewer = ImageViewer("SGM Disparity Heatmap")
        self.disp_pcd_viewer = PointCloudViewer("3D Point Cloud")

        disp_container_layout.addWidget(self.disp_heatmap_viewer)
        disp_container_layout.addWidget(self.disp_pcd_viewer)

        self._update_disp_container_visibility()

        self.yolo_log_viewer = QPlainTextEdit()
        self.yolo_log_viewer.setReadOnly(True)
        self.yolo_log_viewer.setStyleSheet("""
            QPlainTextEdit {
                background-color: #1e1e1e;
                color: #d4d4d4;
                font-family: Consolas, 'Courier New', monospace;
                font-size: 13px;
                border: 2px solid #555;
                border-radius: 4px;
                padding: 8px;
            }
        """)

        self.connected_stacked.addWidget(self.left_viewer)
        self.connected_stacked.addWidget(self.right_viewer)
        self.connected_stacked.addWidget(self.disp_container)
        self.connected_stacked.addWidget(self.yolo_log_viewer)

        self.debug_viewer = ImageViewer("SGM Debug - SW vs FPGA Comparison")
        self.connected_stacked.addWidget(self.debug_viewer)

        connected_layout.addWidget(self.connected_stacked)

        self.stacked.addWidget(self.connected_widget)

        layout.addWidget(control_group)

        calib_group = QGroupBox("Focal Length Calibration")
        calib_layout = QHBoxLayout(calib_group)

        self.calib_btn = QPushButton("Calibrate F")
        self.calib_btn.setCheckable(True)
        self.calib_btn.toggled.connect(self._on_calibrate_toggle)

        self.calib_dist_input = QLineEdit()
        self.calib_dist_input.setPlaceholderText("Measured dist (cm)")
        self.calib_dist_input.setMaximumWidth(120)
        self.calib_dist_input.setEnabled(False)

        self.calib_add_btn = QPushButton("Add Sample")
        self.calib_add_btn.clicked.connect(self._on_calib_add_sample)
        self.calib_add_btn.setEnabled(False)

        self.calib_status_label = QLabel("Samples: 0 | f = --- px")

        self.calib_apply_btn = QPushButton("Apply")
        self.calib_apply_btn.clicked.connect(self._on_calib_apply)
        self.calib_apply_btn.setEnabled(False)

        calib_layout.addWidget(self.calib_btn)
        calib_layout.addWidget(QLabel("Dist:"))
        calib_layout.addWidget(self.calib_dist_input)
        calib_layout.addWidget(self.calib_add_btn)
        calib_layout.addWidget(self.calib_status_label)
        calib_layout.addStretch()
        calib_layout.addWidget(self.calib_apply_btn)

        self.calib_group = calib_group
        self.calib_group.setEnabled(False)

        layout.addWidget(calib_group)
        layout.addWidget(self.stacked, 1)

        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)

        self._latency_label = QLabel("FPS: -- | YOLO: -- | DISP: -- | DIST: -- | Total: --")
        self._latency_label.setStyleSheet(
            "padding: 0 10px; color: #aaaaaa; font-size: 12px;"
        )
        self.status_bar.addPermanentWidget(self._latency_label)

        self.camera_combo.addItem("Detecting cameras...", None)
        self._update_ui_state()

    def _setup_menu(self):
        menubar = self.menuBar()
        self.view_menu = menubar.addMenu("视图")

        self.view_group = QActionGroup(self)
        self.view_group.setExclusive(True)

        self.view_left_action = QAction("左目摄像头画面", self, checkable=True)
        self.view_left_action.setChecked(True)

        self.view_right_action = QAction("右目摄像头画面", self, checkable=True)
        self.view_disp_action = QAction("视差图画面", self, checkable=True)
        self.view_yolo_action = QAction("YOLO检测日志", self, checkable=True)
        self.view_debug_action = QAction("SGM Debug对比", self, checkable=True)

        self.view_left_action.triggered.connect(
            lambda: self._switch_view(ViewMode.LEFT)
        )
        self.view_right_action.triggered.connect(
            lambda: self._switch_view(ViewMode.RIGHT)
        )
        self.view_disp_action.triggered.connect(
            lambda: self._switch_view(ViewMode.DISPARITY)
        )
        self.view_yolo_action.triggered.connect(
            lambda: self._switch_view(ViewMode.YOLO_LOG)
        )
        self.view_debug_action.triggered.connect(
            lambda: self._switch_view(ViewMode.DEBUG)
        )

        self.view_group.addAction(self.view_left_action)
        self.view_group.addAction(self.view_right_action)
        self.view_group.addAction(self.view_disp_action)
        self.view_group.addAction(self.view_yolo_action)
        self.view_group.addAction(self.view_debug_action)

        self.view_menu.addAction(self.view_left_action)
        self.view_menu.addAction(self.view_right_action)
        self.view_menu.addAction(self.view_disp_action)
        self.view_menu.addAction(self.view_yolo_action)
        self.view_menu.addAction(self.view_debug_action)
        self.view_menu.setEnabled(False)

    def _setup_timer(self):
        self.timer = QTimer()
        self.timer.timeout.connect(self._update_frames)
        self.timer.setInterval(FRAME_INTERVAL_MS)

    def _switch_view(self, mode):
        self._view_mode = mode
        self.connected_stacked.setCurrentIndex(mode)
        if mode == ViewMode.LEFT:
            self.status_bar.showMessage("View: Left Camera")
        elif mode == ViewMode.RIGHT:
            self.status_bar.showMessage("View: Right Camera")
        elif mode == ViewMode.DISPARITY:
            self.status_bar.showMessage("View: Disparity Map")
        elif mode == ViewMode.YOLO_LOG:
            self.status_bar.showMessage("View: YOLO Detection Log")
        elif mode == ViewMode.DEBUG:
            self.status_bar.showMessage("View: SGM Debug Comparison")

    def _on_calibrate_toggle(self, checked):
        self._calib_mode = checked
        self.calib_dist_input.setEnabled(checked)
        self.calib_add_btn.setEnabled(checked)
        if not checked:
            self._calib_disp_values.clear()
            self.calib_status_label.setText(
                f"Samples: {len(self._calib_samples)} | "
                f"f = {self._calib_current_focal:.0f} px"
            )

    def _compute_average_focal(self):
        focal_estimates = []
        for d, z in self._calib_samples:
            f = calibrate_focal_from_disparity(d, z)
            if f is not None and f > 0:
                focal_estimates.append(f)
        if not focal_estimates:
            return None
        return sum(focal_estimates) / len(focal_estimates)

    def _on_calib_add_sample(self):
        if not self._calib_disp_values:
            self.status_bar.showMessage("No detections with valid disparity to calibrate")
            return
        try:
            dist_cm = float(self.calib_dist_input.text().strip())
        except ValueError:
            self.status_bar.showMessage("Enter a valid measured distance in cm")
            return
        if dist_cm <= 0:
            self.status_bar.showMessage("Distance must be positive")
            return
        disp_val = self._calib_disp_values[0]
        if disp_val is None or disp_val <= 0:
            self.status_bar.showMessage("No valid disparity for first detection")
            return
        self._calib_samples.append((disp_val, dist_cm))
        avg_f = self._compute_average_focal()
        if avg_f is None:
            self._calib_samples.pop()
            self.status_bar.showMessage("All samples invalid, sample rejected")
            return
        self._calib_current_focal = avg_f
        self.calib_status_label.setText(
            f"Samples: {len(self._calib_samples)} | "
            f"d={disp_val:.0f}px  Z={dist_cm:.0f}cm  "
            f"f={avg_f:.0f} px"
        )
        self.calib_apply_btn.setEnabled(True)
        self.calib_dist_input.clear()
        self.status_bar.showMessage(
            f"Sample added: d={disp_val:.0f}, Z={dist_cm:.0f}cm, "
            f"f={avg_f:.0f}px | Use more distances for best accuracy"
        )

    def _on_calib_apply(self):
        if not self._calib_samples:
            return
        avg_f = self._compute_average_focal()
        if avg_f is None:
            self.status_bar.showMessage("No valid samples to apply")
            return
        self._calib_current_focal = avg_f
        config.STEREO_FOCAL_LENGTH_PX = avg_f
        self.calib_status_label.setText(
            f"APPLIED: f = {avg_f:.0f} px "
            f"(from {len(self._calib_samples)} samples)"
        )
        self.calib_apply_btn.setEnabled(False)
        self.status_bar.showMessage(
            f"Focal length updated: {avg_f:.0f} px"
        )

    def _update_calib_data(self):
        self._calib_disp_values.clear()
        for det in self.detections:
            d = compute_bbox_disparity(self._pipeline.disp_map if self._pipeline else None, det["bbox"])
            self._calib_disp_values.append(d)
        valid = [v for v in self._calib_disp_values if v is not None]
        if valid:
            self.calib_status_label.setText(
                f"Samples: {len(self._calib_samples)} | "
                f"1st d={valid[0]:.0f}px | "
                f"f={self._calib_current_focal:.0f} px"
            )
            self.status_bar.showMessage(
                f"CALIBRATION MODE | Target d={valid[0]:.0f}px | "
                f"Enter measured distance and click Add Sample"
            )
        else:
            self._calib_disp_values.clear()
            self.calib_status_label.setText(
                f"Samples: {len(self._calib_samples)} | "
                f"No valid disparity"
            )

    def _on_defect_toggle(self, checked):
        if self.state != AppState.CONNECTED:
            return

        if checked:
            self.defect_btn.setText("缺陷识别: ON")
            self.status_bar.showMessage("Defect detection enabled")
            if self.detections:
                self._log_current_detections()
        else:
            self.defect_btn.setText("缺陷识别: OFF")
            self.status_bar.showMessage("Defect detection disabled")

        self._update_measure_button_visibility()

    def _on_toggle_debug(self, checked):
        if checked:
            self._debug_mode = True
            self.debug_btn.setText("SGM Debug: ON")
            self.status_bar.showMessage("Loading rectification LUT for debug...")
            if not self._debug_lut_loaded:
                try:
                    load_lut(config.DEBUG_RECTIFICATION_LUT_DIR)
                    self._debug_lut_loaded = True
                    self.status_bar.showMessage("SGM Debug: LUT loaded OK")
                except Exception as e:
                    self.status_bar.showMessage(f"SGM Debug: LUT load FAILED - {e}")
                    self._debug_mode = False
                    self.debug_btn.setChecked(False)
                    return
            self._switch_view(ViewMode.DEBUG)
        else:
            self._debug_mode = False
            self.debug_btn.setText("SGM Debug: OFF")
            self._debug_last_stats = None
            self.status_bar.showMessage("SGM Debug disabled")

    def _sgm_debug_wrapper(self, frame, left_crop, right_crop):
        try:
            self._process_sgm_debug(frame, left_crop, right_crop)
        finally:
            self._sgm_debug_running = False

    def _process_sgm_debug(self, frame, left_crop, right_crop):
        import time
        t0 = time.time()

        left_gray = cv2.cvtColor(left_crop, cv2.COLOR_BGR2GRAY)
        right_gray = cv2.cvtColor(right_crop, cv2.COLOR_BGR2GRAY)

        left_rect = rectify_left_gray(left_gray)
        right_rect = rectify_right_gray(right_gray)

        t_rect = time.time()

        sw_encoded, sw_float, sw_int, sw_conf = compute_sgm_disparity(left_rect, right_rect)

        t_sgm = time.time()

        disp_crop = crop_sgm_disparity(frame)

        fpga_float = None
        if disp_crop is not None:
            fpga_float = restore_disparity_map(disp_crop)
        else:
            fpga_float = None

        t_decode = time.time()

        stats = None
        if sw_float is not None and fpga_float is not None and disp_crop is not None:
            stats = sgm_compare(sw_encoded, disp_crop, sw_float)
            self._debug_sw_disp_map = sw_float
            self._debug_fpga_disp_map = fpga_float
            self._debug_diff_map = stats["diff_map"] if stats else None

        self._debug_last_stats = stats

        debug_vis = self._build_debug_visualization(
            left_rect, right_rect, sw_float, fpga_float, stats, left_gray, right_gray
        )

        t_viz = time.time()
        stat_text = self._debug_stats_text(stats, t_rect - t0, t_sgm - t_rect, t_decode - t_sgm)

        self._sgm_debug_ready.emit(debug_vis, stat_text)

    def _sgm_debug_show(self, debug_vis, stat_text):
        if self._view_mode == ViewMode.DEBUG:
            self.debug_viewer.display_image(debug_vis)
        self.status_bar.showMessage(stat_text)

    def _build_debug_visualization(self, left_rect, right_rect, sw_float, fpga_float, stats,
                                    left_raw, right_raw):
        disp_max = config.SGM_DISP_PARAMS["MAX_DISPARITY"]

        def disp_to_heatmap(disp):
            vis = np.zeros((480, 640, 3), dtype=np.uint8)
            vis[:] = (30, 30, 30)
            if disp is None:
                return vis
            valid = disp >= 0
            if np.any(valid):
                norm = (1.0 - disp[valid].astype(np.float32) / disp_max) * 255.0
                norm = np.clip(norm, 0, 255).astype(np.uint8)
                colored = cv2.applyColorMap(norm, cv2.COLORMAP_JET)
                vis[valid] = colored.reshape(-1, 3)
            invalid = ~valid
            if np.any(invalid):
                vis[invalid] = (0, 0, 200)
            return vis

        sw_vis = disp_to_heatmap(sw_float)
        fpga_vis = disp_to_heatmap(fpga_float)

        diff_vis = np.zeros((480, 640, 3), dtype=np.uint8)
        if stats is not None and stats["diff_map"] is not None:
            diff_map = stats["diff_map"]
            abs_diff = np.abs(diff_map)
            max_abs = np.max(abs_diff)
            if max_abs > 0:
                norm = (abs_diff / max_abs * 255).clip(0, 255).astype(np.uint8)
                diff_vis = cv2.applyColorMap(norm, cv2.COLORMAP_HOT)

        rect_pair = np.hstack([left_rect, right_rect]) if left_rect is not None else np.zeros((480, 1280), dtype=np.uint8)
        rect_pair_color = cv2.cvtColor(rect_pair, cv2.COLOR_GRAY2BGR)

        raw_pair_left = cv2.cvtColor(left_raw, cv2.COLOR_GRAY2BGR)
        raw_pair_right = cv2.cvtColor(right_raw, cv2.COLOR_GRAY2BGR)
        raw_pair = np.hstack([raw_pair_left, raw_pair_right])

        triple = np.hstack([sw_vis, fpga_vis, diff_vis])
        triple_resized = cv2.resize(triple, (1280, 480))

        cv2.putText(triple_resized, "SW SGM", (5, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2)
        cv2.putText(triple_resized, "FPGA SGM", (430, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2)
        cv2.putText(triple_resized, "|SW-FPGA|", (860, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 2)

        cv2.putText(rect_pair_color, "Left (rectified)", (5, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)
        cv2.putText(rect_pair_color, "Right (rectified)", (645, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 2)

        cv2.putText(raw_pair, "Left (raw)", (5, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)
        cv2.putText(raw_pair, "Right (raw)", (645, 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 255), 2)

        combined = np.vstack([rect_pair_color, triple_resized, raw_pair])

        if stats:
            info_h = 40
            info_bar = np.zeros((info_h, 1280, 3), dtype=np.uint8)
            info_bar[:] = (40, 40, 40)
            text = f"RMSE:{stats['rmse']:.2f}px  MaxDiff:{stats['max_diff']:.1f}px  MeanAbs:{stats['mean_abs_diff']:.2f}px  Corr:{stats['correlation']:.3f}  SW:{stats['sw_valid_pct']:.0f}%  FPGA:{stats['fpga_valid_pct']:.0f}%"
            cv2.putText(info_bar, text, (10, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200, 200, 200), 1)
            combined = np.vstack([info_bar, combined])

        return combined

    def _debug_stats_text(self, stats, t_rect, t_sgm, t_decode):
        parts = []
        parts.append(f"Rect:{t_rect*1000:.0f}ms SGM:{t_sgm*1000:.0f}ms Decode:{t_decode*1000:.0f}ms")
        if stats:
            parts.append(f"BothValid:{stats['num_both_valid']}")
            parts.append(f"RMSE:{stats['rmse']:.2f}px MaxDiff:{stats['max_diff']:.1f}px")
            parts.append(f"MeanAbsErr:{stats['mean_abs_diff']:.2f}px Corr:{stats['correlation']:.3f}")
            parts.append(f"SW_valid:{stats['sw_valid_pct']:.1f}% FPGA_valid:{stats['fpga_valid_pct']:.1f}%")
        return "SGM Debug | " + " | ".join(parts)

    def _log_current_detections(self):
        if not self.detections:
            self._append_yolo_log("[No defects detected]")
            return

        timestamp = QDateTime.currentDateTime().toString("yyyy-MM-dd hh:mm:ss")
        self._append_yolo_log(f"=== Defect Detection @ {timestamp} ===")
        for i, det in enumerate(self.detections, 1):
            x1, y1, x2, y2 = det["bbox"]
            self._append_yolo_log(
                f"  [{i}] {det['class']} | "
                f"Conf: {det['conf']:.0%} | "
                f"BBox: ({x1},{y1})-({x2},{y2})"
            )
        self._append_yolo_log(f"Total: {len(self.detections)} defect(s)")
        self._append_yolo_log("")

    def _append_yolo_log(self, text):
        self._yolo_log_entries.append(text)
        self.yolo_log_viewer.appendPlainText(text)
        if self._view_mode == ViewMode.YOLO_LOG:
            self.yolo_log_viewer.moveCursor(QTextCursor.End)

    def _refresh_camera_list_async(self):
        self.camera_combo.blockSignals(True)
        self.camera_combo.clear()
        self.camera_combo.addItem("Detecting cameras...", None)
        self.camera_combo.blockSignals(False)
        self.status_bar.showMessage("Scanning for cameras...")

        if self.list_worker_thread is not None and self.list_worker_thread.isRunning():
            self.list_worker_thread.quit()
            self.list_worker_thread.wait(500)

        self.list_worker = CameraListWorker()
        self.list_worker_thread = QThread(self)
        self.list_worker.moveToThread(self.list_worker_thread)
        self.list_worker_thread.started.connect(self.list_worker.run)
        self.list_worker.finished.connect(self._on_camera_list_received)
        self.list_worker.finished.connect(self.list_worker_thread.quit)
        self.list_worker_thread.finished.connect(self.list_worker.deleteLater)
        self.list_worker_thread.start()

    def _on_camera_list_received(self, available):
        self.camera_combo.blockSignals(True)
        self.camera_combo.clear()
        if not available:
            self.camera_combo.addItem("No camera detected", None)
            self.status_bar.showMessage("No cameras found. Check connection.")
        else:
            for cam_id in available:
                self.camera_combo.addItem(f"Camera {cam_id}", cam_id)
            self.status_bar.showMessage(f"Found {len(available)} camera(s)")
        self.camera_combo.blockSignals(False)
        self.list_worker_thread = None
        self.list_worker = None

    def _get_camera_id(self):
        manual_text = self.manual_input.text().strip()
        if manual_text:
            try:
                return int(manual_text)
            except ValueError:
                return None
        return self.camera_combo.currentData()

    def _on_preview_clicked(self):
        if self.state != AppState.IDLE:
            return
        cam_id = self._get_camera_id()
        if cam_id is None:
            self.status_bar.showMessage("No valid camera ID. Select from list or enter manually.")
            return

        self.preview_btn.setEnabled(False)
        self.status_bar.showMessage("Opening camera...")

        self.worker = CameraOpenWorker(cam_id)
        self.worker_thread = QThread(self)
        self.worker.moveToThread(self.worker_thread)
        self.worker_thread.started.connect(self.worker.run)
        self.worker.opened.connect(self._on_camera_opened)
        self.worker.failed.connect(self._on_camera_failed)
        self.worker.progress.connect(self.status_bar.showMessage)
        self.worker.opened.connect(self.worker_thread.quit)
        self.worker.failed.connect(self.worker_thread.quit)
        self.worker_thread.finished.connect(self.worker.deleteLater)
        self.worker_thread.finished.connect(self._on_worker_finished)
        self.worker_thread.start()

    def _on_worker_finished(self):
        self.worker_thread = None
        self.worker = None

    def _on_camera_opened(self, cam):
        self.camera.release()
        self.camera = cam
        self.state = AppState.PREVIEW
        self._update_ui_state()
        self._first_frame_received = False
        self.timer.start()
        self.stacked.setCurrentIndex(0)
        backend = CameraCapture.BACKEND_NAMES.get(self.camera.backend, "Unknown")
        self.status_bar.showMessage(
            f"Camera opened ({backend}), receiving first frame..."
        )

    def _on_camera_failed(self, msg):
        self.status_bar.showMessage(f"Failed: {msg}")
        self._update_ui_state()

    def _on_connect_clicked(self):
        if self.state != AppState.PREVIEW:
            return
        self.state = AppState.CONNECTED
        self._update_ui_state()
        self.stacked.setCurrentIndex(1)

        self.detector = PCBDetector(config.MODEL_WEIGHTS_PATH)
        self.detector.inference_skip = config.MODEL_INFERENCE_SKIP
        device = self.detector.load()
        self.detections = []

        self.pcb_board_detector = PCBBoardDetector()
        try:
            self.pcb_board_detector.load()
        except FileNotFoundError:
            self.status_bar.showMessage(
                "PCB board detector weights not found. "
                "Run train_pcb_detector.py first."
            )
            self.pcb_board_detector = None
        except Exception as e:
            self.status_bar.showMessage(f"PCB board detector load failed: {e}")
            self.pcb_board_detector = None

        self._latency_tracker.reset()

        self._pipeline = ParallelPipeline(
            defect_detector=self.detector,
            board_detector=self.pcb_board_detector,
            pnp_processor=self.pnp_processor,
            heatmap_active=self._heatmap_active,
            pcd_active=self._pcd_active,
        )

        self._switch_view(ViewMode.LEFT)
        self.view_menu.setEnabled(True)

        self.left_viewer.roi_selected.connect(self._on_roi_selected)

        backend = CameraCapture.BACKEND_NAMES.get(self.camera.backend, "Unknown")
        self.status_bar.showMessage(
            f"Connected - Camera {self.camera.camera_id} ({backend}) | "
            f"Defect Detector: {device.upper()}"
        )

    def _on_toggle_heatmap(self, checked):
        if self.state != AppState.CONNECTED:
            return
        self._heatmap_active = checked
        if self._pipeline is not None:
            self._pipeline._heatmap_active = checked
        self._update_disp_container_visibility()
        self._update_ui_state()

        if self._heatmap_active:
            self.status_bar.showMessage("SGM Heatmap: ON")
        else:
            self.status_bar.showMessage("SGM Heatmap: OFF")
            if not self._pcd_active:
                self._disp_map = None

        self._update_measure_button_visibility()

    def _on_toggle_pcd(self, checked):
        if self.state != AppState.CONNECTED:
            return
        self._pcd_active = checked
        if self._pipeline is not None:
            self._pipeline._pcd_active = checked
        self._update_disp_container_visibility()
        self._update_ui_state()

        if self._pcd_active:
            self.status_bar.showMessage("3D Point Cloud: ON")
        else:
            self.status_bar.showMessage("3D Point Cloud: OFF")
            if not self._heatmap_active:
                self._disp_map = None

    def _on_toggle_measure(self, checked):
        if self.state != AppState.CONNECTED:
            return
        if checked and not self._can_measure():
            self.measure_btn.blockSignals(True)
            self.measure_btn.setChecked(False)
            self.measure_btn.blockSignals(False)
            return

        self._measure_mode = checked
        self.left_viewer.set_roi_mode(checked)

        if not checked:
            self._measure_roi = None
            self._measure_stats = None
            self._measure_distance = None

        self._update_ui_state()

        if self._measure_mode:
            self.status_bar.showMessage("Manual Measure: Draw ROI on left camera")
        else:
            self.status_bar.showMessage("Manual Measure: OFF")

    def _can_measure(self):
        return self._heatmap_active and not self.defect_btn.isChecked()

    def _update_measure_button_visibility(self):
        can = self._can_measure()
        self.measure_btn.setVisible(can)
        if not can and self._measure_mode:
            self.measure_btn.blockSignals(True)
            self.measure_btn.setChecked(False)
            self.measure_btn.blockSignals(False)

    def _on_roi_selected(self, x1, y1, x2, y2):
        pipeline_disp = self._pipeline.disp_map if self._pipeline else None
        if not self._measure_mode or pipeline_disp is None:
            return

        self._measure_roi = (x1, y1, x2, y2)

        stats = compute_roi_disparity_stats(pipeline_disp, x1, y1, x2, y2)
        self._measure_stats = stats

        if stats is not None:
            baseline = config.STEREO_PARAMS["BASELINE_CM"]
            focal = config.STEREO_FOCAL_LENGTH_PX
            dist = disparity_to_distance(stats["mean_disp"], baseline, focal)
            self._measure_distance = dist

            msg = (f"ROI ({x1},{y1})-({x2},{y2}): "
                   f"MeanDisp={stats['mean_disp']:.2f}, "
                   f"Var={stats['var_disp']:.2f}, "
                   f"Std={stats['std_disp']:.2f}")

            if dist is not None:
                if dist < 100.0:
                    msg += f", Dist={dist:.1f}cm"
                else:
                    msg += f", Dist={dist/100:.2f}m"
            else:
                msg += ", Dist=Invalid"

            msg += f" | Valid: {stats['valid_count']}/{stats['total_count']} ({stats['valid_ratio']:.1f}%)"
            self.status_bar.showMessage(msg)
        else:
            self._measure_distance = None
            self.status_bar.showMessage(
                f"ROI ({x1},{y1})-({x2},{y2}): No valid disparity"
            )

    def _update_disp_container_visibility(self):
        show_heatmap = self._heatmap_active
        show_pcd = self._pcd_active

        self.disp_heatmap_viewer.setVisible(show_heatmap)
        self.disp_pcd_viewer.setVisible(show_pcd)

        if not show_heatmap:
            self.disp_heatmap_viewer.clear()
        if not show_pcd:
            self.disp_pcd_viewer.clear()

    def _on_add_pnp_template(self):
        from gui.pnp_template_dialog import PnPTemplateDialog

        dialog = PnPTemplateDialog(self)
        if dialog.exec_():
            processor = dialog.get_processor()
            if processor is not None and processor.template_loaded:
                self.pnp_processor = processor
                self.pnp_template_loaded = True
                if self._pipeline is not None:
                    self._pipeline._pnp_processor = processor
                info = dialog.get_template_info()
                self.status_bar.showMessage(
                    f"PnP template loaded: {info['width_cm']:.1f}x{info['height_cm']:.1f} cm, "
                    f"{info['n_features']} ORB features"
                )
            else:
                self.status_bar.showMessage(
                    "PnP template registration failed or cancelled"
                )
        else:
            self.status_bar.showMessage(
                "PnP template registration cancelled"
            )

    def _disconnect(self):
        self._abort_worker()
        self.timer.stop()
        self.camera.release()
        if self.detector is not None:
            self.detector.unload()
            self.detector = None
        if self.pcb_board_detector is not None:
            self.pcb_board_detector.unload()
            self.pcb_board_detector = None
        self.detections = []
        self._heatmap_active = False
        self._pcd_active = False
        self.heatmap_btn.setChecked(False)
        self.pcd_btn.setChecked(False)
        self._measure_mode = False
        self._measure_roi = None
        self._measure_stats = None
        self._measure_distance = None
        self.measure_btn.setChecked(False)
        self.measure_btn.setVisible(False)
        self.left_viewer.set_roi_mode(False)
        self._disp_map = None
        self._view_mode = ViewMode.LEFT
        self.state = AppState.IDLE
        self._update_ui_state()
        self._update_disp_container_visibility()
        self.preview_viewer.clear()
        self.left_viewer.clear()
        self.right_viewer.clear()
        self.disp_heatmap_viewer.clear()
        self.disp_pcd_viewer.clear()
        self.stacked.setCurrentIndex(0)
        self.view_menu.setEnabled(False)
        self.view_left_action.setChecked(True)
        self._yolo_log_entries.clear()
        self.yolo_log_viewer.clear()
        self._calib_mode = False
        self._calib_disp_values.clear()
        self.calib_btn.setChecked(False)
        self.calib_dist_input.setEnabled(False)
        self.calib_add_btn.setEnabled(False)
        self.calib_status_label.setText(
            f"Samples: {len(self._calib_samples)} | "
            f"f = {self._calib_current_focal:.0f} px"
        )
        self.pcb_board_detection = None
        self.pcb_board_distance = None
        self.pnp_processor = None
        self.pnp_template_loaded = False
        self.pnp_pose_result = None
        self.pnp_similarity = 0.0
        if self._pipeline is not None:
            self._pipeline.shutdown()
            self._pipeline = None
        self._latency_tracker.reset()
        self._latency_label.setText("FPS: -- | PCB: -- | YOLO: -- | DISP: -- | DIST: -- | Total: --")
        self.status_bar.showMessage("Disconnected")

    def _abort_worker(self):
        if self.worker_thread is not None and self.worker_thread.isRunning():
            self.worker_thread.quit()
            self.worker_thread.wait(1000)
            self.worker_thread = None
            self.worker = None

    def _update_ui_state(self):
        if self.state == AppState.IDLE:
            self.camera_combo.setEnabled(True)
            self.manual_input.setEnabled(True)
            self.preview_btn.setEnabled(True)
            self.connect_btn.setEnabled(False)
            self.connect_btn.setText("Connect")
            self.disconnect_btn.setEnabled(False)
            self.heatmap_btn.setEnabled(False)
            self.heatmap_btn.setText("Heatmap: OFF")
            self.pcd_btn.setEnabled(False)
            self.pcd_btn.setText("3D Point Cloud: OFF")
            self.defect_btn.setEnabled(False)
            self.pnp_btn.setEnabled(False)
            self.stacked.setCurrentIndex(0)
        elif self.state == AppState.PREVIEW:
            self.camera_combo.setEnabled(False)
            self.manual_input.setEnabled(False)
            self.preview_btn.setEnabled(False)
            self.connect_btn.setEnabled(True)
            self.connect_btn.setText("Connect")
            self.disconnect_btn.setEnabled(True)
            self.heatmap_btn.setEnabled(False)
            self.heatmap_btn.setText("Heatmap: OFF")
            self.pcd_btn.setEnabled(False)
            self.pcd_btn.setText("3D Point Cloud: OFF")
            self.defect_btn.setEnabled(False)
            self.pnp_btn.setEnabled(False)
            self.stacked.setCurrentIndex(0)
        elif self.state == AppState.CONNECTED:
            self.camera_combo.setEnabled(False)
            self.manual_input.setEnabled(False)
            self.preview_btn.setEnabled(False)
            self.connect_btn.setEnabled(False)
            self.connect_btn.setText("Connect")
            self.disconnect_btn.setEnabled(True)
            self.heatmap_btn.setEnabled(True)
            self.heatmap_btn.setText("Heatmap: ON" if self._heatmap_active else "Heatmap: OFF")
            self.pcd_btn.setEnabled(True)
            self.pcd_btn.setText("3D Point Cloud: ON" if self._pcd_active else "3D Point Cloud: OFF")
            self.defect_btn.setEnabled(True)
            self.pnp_btn.setEnabled(True)
            self.calib_group.setEnabled(True)
            self.stacked.setCurrentIndex(1)

            self._update_measure_button_visibility()

    def _update_frames(self):
        self._latency_tracker.tick_frame()
        self._latency_tracker.start_stage('total_frame')

        self._latency_tracker.start_stage('camera_read')
        frame = self.camera.read_frame()
        self._latency_tracker.end_stage('camera_read')
        if frame is None:
            self._latency_tracker.end_stage('total_frame')
            return

        if not self._first_frame_received:
            self._first_frame_received = True
            backend = CameraCapture.BACKEND_NAMES.get(self.camera.backend, "Unknown")
            self.status_bar.showMessage(
                f"Preview - Camera {self.camera.camera_id} ({backend}) | "
                f"{self.camera.frame_width}x{self.camera.frame_height} @ 30fps"
            )

        if self.state == AppState.PREVIEW:
            self.preview_viewer.display_image(frame)

        elif self.state == AppState.CONNECTED:
            self._handle_connected_frame(frame)

        self._latency_tracker.end_stage('total_frame')
        self._update_latency_display()

    def _handle_connected_frame(self, frame):
        if self._pipeline is not None and self._pipeline.has_error:
            error_msg = self._pipeline.last_error
            self.status_bar.showMessage(f"Pipeline Error: {error_msg}")
            self._pipeline.reset_error()

        if self._pipeline is not None and self._parallel_enabled:
            ts, left_crop, right_crop = self._pipeline.submit_frame(frame)

            disp_enabled = self._heatmap_active or self._pcd_active
            if disp_enabled:
                self._latency_tracker.start_stage('disparity_pipeline')
                self._latency_tracker.end_stage('disparity_pipeline')
            if self.pcb_board_detector is not None and self.pcb_board_detector.is_loaded:
                self._latency_tracker.start_stage('pcb_board_detect')
                self._latency_tracker.end_stage('pcb_board_detect')
            if self.detector is not None and self.defect_btn.isChecked():
                self._latency_tracker.start_stage('yolo_inference')
                self._latency_tracker.end_stage('yolo_inference')

            merged = self._pipeline.get_merged()
            if merged is not None:
                left_crop = merged['left_crop']
                right_crop = merged['right_crop']
                disp_map = merged['disp_map']
                disp_vis = merged['disp_vis']
                board_det = merged['board_detection']
                defect_dets = merged['defect_detections']

                if disp_vis is not None and self._heatmap_active:
                    self.disp_heatmap_viewer.display_image(disp_vis)

                if disp_map is not None and self._pcd_active:
                    now = time.time()
                    elapsed = now - self._last_pcd_update_time
                    if elapsed >= self._pcd_update_interval:
                        self._last_pcd_update_time = now
                        pcd_points = generate_pointcloud_from_disparity(disp_map)
                        if pcd_points is not None:
                            self.disp_pcd_viewer.update_pointcloud(pcd_points)

                if disp_map is not None and self._view_mode == ViewMode.DISPARITY:
                    stats = get_disparity_stats(disp_map)
                    if stats:
                        msg_parts = []
                        if self._heatmap_active:
                            msg_parts.append(f"Valid: {stats['valid_ratio']:.1f}%")
                            msg_parts.append(f"Range: [{stats.get('min_disp', '?')}, {stats.get('max_disp', '?')}]")
                            msg_parts.append(f"Mean: {stats.get('mean_disp', 0):.1f}")
                        if self._pcd_active:
                            pcd_hz = config.PCD_PARAMS["REFRESH_RATE_HZ"]
                            msg_parts.append(f"PCD@{pcd_hz}Hz")
                        self.status_bar.showMessage(
                            "SGM Disp | " + " | ".join(msg_parts)
                        )

                if left_crop is not None:
                    disp_available = disp_map is not None
                    left_display = left_crop.copy()

                    self._pipeline.update_pnp(left_crop, board_det)

                    if board_det is not None:
                        left_display = draw_pcb_board_detection(
                            left_display,
                            board_det,
                            distance=self._pipeline.board_distance,
                            disparity_available=disp_available,
                        )

                    if self._pipeline.pnp_pose_result is not None:
                        left_display = self._pnp_processor.draw_pose(
                            left_display, self._pipeline.pnp_pose_result
                        )

                    defect_enabled = self.defect_btn.isChecked()
                    if defect_enabled and defect_dets:
                        left_display = draw_pcb_detections(
                            left_display, defect_dets, self._pipeline.last_distances,
                            disparity_available=disp_available,
                        )

                    if self._measure_mode and self._measure_roi is not None:
                        left_display = draw_roi_measure_overlay(
                            left_display,
                            self._measure_roi,
                            self._measure_stats,
                            self._measure_distance,
                        )

                    self.left_viewer.display_image(left_display)

                if right_crop is not None:
                    self.right_viewer.display_image(right_crop)
        else:
            left_crop = crop_left_camera(frame)
            right_crop = crop_right_camera(frame)

            if left_crop is not None:
                left_display = left_crop.copy()
                self.left_viewer.display_image(left_display)
            if right_crop is not None:
                self.right_viewer.display_image(right_crop)

        if self._debug_mode and self._debug_lut_loaded:
            self._debug_frame_counter += 1
            if self._debug_frame_counter % 10 == 0 and not self._sgm_debug_running:
                self._sgm_debug_running = True
                frame_cp = frame.copy()
                lc = crop_left_camera(frame)
                rc = crop_right_camera(frame)
                threading.Thread(
                    target=self._sgm_debug_wrapper,
                    args=(frame_cp, lc, rc),
                    daemon=True
                ).start()

    def _update_latency_display(self):
        if self.state != AppState.CONNECTED:
            self._latency_label.setText("FPS: -- | PCB: -- | YOLO: -- | DISP: -- | DIST: -- | Total: --")
            return

        if not self._latency_tracker.should_update_display(interval=15):
            return

        active_stages = set()
        if self.pcb_board_detector is not None and self.pcb_board_detector.is_loaded:
            active_stages.add('pcb_board_detect')
        if self.detector is not None:
            active_stages.add('yolo_inference')
        if self._heatmap_active or self._pcd_active:
            active_stages.add('disparity_pipeline')
        if (self._heatmap_active or self._pcd_active) and self.detector is not None:
            active_stages.add('distance_compute')
        if self.pnp_template_loaded:
            active_stages.add('pnp_pose')

        status = self._latency_tracker.get_status_string(active_stages)
        self._latency_label.setText(status)

    def closeEvent(self, event):
        self._abort_worker()
        if self.list_worker_thread is not None and self.list_worker_thread.isRunning():
            self.list_worker_thread.quit()
            self.list_worker_thread.wait(500)
        self.timer.stop()
        if self._pipeline is not None:
            self._pipeline.shutdown()
            self._pipeline = None
        self.camera.release()
        if self.detector is not None:
            self.detector.unload()
            self.detector = None
        if self.pcb_board_detector is not None:
            self.pcb_board_detector.unload()
            self.pcb_board_detector = None
        self.pnp_processor = None
        self.pnp_template_loaded = False
        self.pnp_pose_result = None
        event.accept()
