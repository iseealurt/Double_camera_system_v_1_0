import numpy as np
from PyQt5.QtWidgets import QWidget, QVBoxLayout, QLabel, QHBoxLayout, QPushButton
from PyQt5.QtCore import Qt, QTimer
from PyQt5.QtGui import QFont

from utils import config

try:
    import pyqtgraph.opengl as gl
    HAS_PYQTGRAPH_GL = True
except ImportError:
    HAS_PYQTGRAPH_GL = False


class PointCloudViewer(QWidget):
    def __init__(self, title="3D Point Cloud", parent=None):
        super().__init__(parent)
        self.title = title
        self._has_gl = HAS_PYQTGRAPH_GL
        self._last_points = None
        self._auto_range = True
        self._setup_ui()

    def _setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(2)

        header_layout = QHBoxLayout()
        header_layout.setContentsMargins(4, 2, 4, 2)

        self.title_label = QLabel(self.title)
        self.title_label.setStyleSheet("""
            QLabel {
                color: #ccc;
                font-size: 13px;
                font-weight: bold;
            }
        """)
        header_layout.addWidget(self.title_label)

        self.count_label = QLabel("Points: 0")
        self.count_label.setStyleSheet("""
            QLabel {
                color: #888;
                font-size: 11px;
            }
        """)
        header_layout.addWidget(self.count_label)
        header_layout.addStretch()

        self.reset_btn = QPushButton("Reset View")
        self.reset_btn.setFixedWidth(80)
        self.reset_btn.setFixedHeight(22)
        self.reset_btn.setStyleSheet("""
            QPushButton {
                background-color: #3a3a3a;
                color: #ccc;
                border: 1px solid #555;
                border-radius: 3px;
                font-size: 11px;
                padding: 1px 8px;
            }
            QPushButton:hover {
                background-color: #4a4a4a;
            }
        """)
        self.reset_btn.clicked.connect(self._on_reset_view)
        header_layout.addWidget(self.reset_btn)

        layout.addLayout(header_layout)

        if self._has_gl:
            self._gl_widget = gl.GLViewWidget()
            bg = config.PCD_PARAMS.get("BG_COLOR", (0.08, 0.08, 0.12))
            self._gl_widget.setBackgroundColor(bg)
            self._gl_widget.setMinimumSize(320, 240)
            self._setup_gl_scene()
            layout.addWidget(self._gl_widget, 1)
        else:
            fallback = QLabel("3D Point Cloud\n(pyqtgraph + PyOpenGL required)")
            fallback.setAlignment(Qt.AlignCenter)
            fallback.setStyleSheet("""
                QLabel {
                    border: 2px solid #555;
                    border-radius: 4px;
                    background-color: #1e1e1e;
                    color: #888;
                    font-size: 14px;
                }
            """)
            fallback.setMinimumSize(320, 240)
            layout.addWidget(fallback, 1)

    def _setup_gl_scene(self):
        grid = gl.GLGridItem()
        grid.setSize(200, 200)
        grid.setSpacing(20, 20)
        grid.setColor((80, 80, 80, 60))
        self._gl_widget.addItem(grid)

        axis = gl.GLAxisItem()
        axis.setSize(50, 50, 50)
        self._gl_widget.addItem(axis)

        self._scatter = gl.GLScatterPlotItem()
        self._scatter.setGLOptions('translucent')
        self._gl_widget.addItem(self._scatter)

        self._gl_widget.setCameraPosition(distance=200, elevation=30, azimuth=-45)

    def update_pointcloud(self, points):
        if not self._has_gl or points is None or len(points) == 0:
            self.count_label.setText("Points: 0")
            return

        self._last_points = points
        n = len(points)

        pos = points[:, :3]
        color = points[:, 3:6] / 255.0

        self._scatter.setData(
            pos=pos,
            color=color,
            size=config.PCD_PARAMS.get("POINT_SIZE", 3),
            pxMode=True,
        )

        if self._auto_range:
            self._auto_camera_range(pos)

        self.count_label.setText(f"Points: {n}")

    def _auto_camera_range(self, pos):
        if pos is None or len(pos) == 0:
            return

        center = np.mean(pos, axis=0)
        extent = np.max(np.abs(pos - center)) * 1.5
        if extent < 10:
            extent = 50

        self._gl_widget.setCameraPosition(
            pos=center + np.array([extent * 0.8, -extent * 0.6, extent * 0.7]),
            center=center,
        )
        self._auto_range = False

    def clear(self):
        if self._has_gl and hasattr(self, '_scatter'):
            self._scatter.setData(pos=np.zeros((0, 3)))
        self._last_points = None
        self._auto_range = True
        self.count_label.setText("Points: 0")

    def _on_reset_view(self):
        self._auto_range = True
        if self._last_points is not None:
            self._auto_camera_range(self._last_points[:, :3])
        elif self._has_gl:
            self._gl_widget.setCameraPosition(distance=200, elevation=30, azimuth=-45)
