from PyQt5.QtWidgets import QLabel, QWidget, QVBoxLayout
from PyQt5.QtGui import QPixmap, QImage, QPainter, QPen, QColor
from PyQt5.QtCore import Qt, pyqtSignal, QRect, QPoint


class ImageViewer(QWidget):
    roi_selected = pyqtSignal(int, int, int, int)

    def __init__(self, title="", parent=None):
        super().__init__(parent)
        self.title = title
        self._raw_frame = None
        self._roi_mode = False
        self._roi_start = None
        self._roi_end = None
        self._roi_drawing = False
        self.setMouseTracking(True)
        self._setup_ui()

    def _setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)

        self.label = QLabel(self.title)
        self.label.setAlignment(Qt.AlignCenter)
        self.label.setStyleSheet("""
            QLabel {
                border: 2px solid #555;
                border-radius: 4px;
                background-color: #1e1e1e;
                color: #888;
                font-size: 16px;
                font-weight: bold;
            }
        """)
        self.label.setMinimumSize(640, 480)
        self.label.setMouseTracking(True)

        layout.addWidget(self.label)

    def display_image(self, frame):
        if frame is None:
            return

        self._raw_frame = frame.copy()

        h, w, ch = frame.shape
        bytes_per_line = ch * w
        q_img = QImage(frame.tobytes(), w, h, bytes_per_line, QImage.Format_BGR888)
        pixmap = QPixmap.fromImage(q_img)
        scaled = pixmap.scaled(
            self.label.width(),
            self.label.height(),
            Qt.KeepAspectRatio,
            Qt.SmoothTransformation,
        )
        self.label.setPixmap(scaled)

    def set_roi_mode(self, enabled):
        self._roi_mode = enabled
        if not enabled:
            self._roi_start = None
            self._roi_end = None
            self._roi_drawing = False
            self.update()
        self.setCursor(Qt.CrossCursor if enabled else Qt.ArrowCursor)

    def _get_pixmap_geometry(self):
        if self._raw_frame is None:
            return None
        img_h, img_w = self._raw_frame.shape[:2]
        label_w = self.label.width()
        label_h = self.label.height()
        if label_w <= 0 or label_h <= 0:
            return None

        scale = min(label_w / img_w, label_h / img_h)
        disp_w = img_w * scale
        disp_h = img_h * scale
        offset_x = (label_w - disp_w) / 2.0
        offset_y = (label_h - disp_h) / 2.0
        return offset_x, offset_y, scale

    def _widget_to_image_coords(self, pos):
        geo = self._get_pixmap_geometry()
        if geo is None or self._raw_frame is None:
            return None
        offset_x, offset_y, scale = geo
        img_h, img_w = self._raw_frame.shape[:2]

        x = (pos.x() - offset_x) / scale
        y = (pos.y() - offset_y) / scale

        ix = max(0, min(int(x), img_w - 1))
        iy = max(0, min(int(y), img_h - 1))
        return ix, iy

    def _image_to_widget_coords(self, ix, iy):
        geo = self._get_pixmap_geometry()
        if geo is None:
            return QPoint(0, 0)
        offset_x, offset_y, scale = geo
        wx = int(ix * scale + offset_x)
        wy = int(iy * scale + offset_y)
        return QPoint(wx, wy)

    def mousePressEvent(self, event):
        if not self._roi_mode or event.button() != Qt.LeftButton:
            super().mousePressEvent(event)
            return
        pt = self._widget_to_image_coords(event.pos())
        if pt is None:
            return
        self._roi_start = pt
        self._roi_end = pt
        self._roi_drawing = True

    def mouseMoveEvent(self, event):
        if not self._roi_drawing:
            super().mouseMoveEvent(event)
            return
        pt = self._widget_to_image_coords(event.pos())
        if pt is None:
            return
        self._roi_end = pt
        self.update()

    def mouseReleaseEvent(self, event):
        if not self._roi_drawing or event.button() != Qt.LeftButton:
            super().mouseReleaseEvent(event)
            return
        pt = self._widget_to_image_coords(event.pos())
        if pt is None:
            return
        self._roi_end = pt
        self._roi_drawing = False

        x1 = min(self._roi_start[0], self._roi_end[0])
        y1 = min(self._roi_start[1], self._roi_end[1])
        x2 = max(self._roi_start[0], self._roi_end[0])
        y2 = max(self._roi_start[1], self._roi_end[1])

        if x2 - x1 > 2 and y2 - y1 > 2:
            self.roi_selected.emit(x1, y1, x2, y2)

        self.update()

    def paintEvent(self, event):
        super().paintEvent(event)
        if not self._roi_mode or self._roi_start is None or self._roi_end is None:
            return

        p1 = self._image_to_widget_coords(self._roi_start[0], self._roi_start[1])
        p2 = self._image_to_widget_coords(self._roi_end[0], self._roi_end[1])

        x = min(p1.x(), p2.x())
        y = min(p1.y(), p2.y())
        w = abs(p2.x() - p1.x())
        h = abs(p2.y() - p1.y())

        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing, False)

        pen = QPen(QColor(0, 255, 0), 2, Qt.SolidLine)
        painter.setPen(pen)
        painter.setBrush(QColor(0, 255, 0, 40))
        painter.drawRect(QRect(x, y, w, h))
        painter.end()

    def clear(self):
        self.label.clear()
        self.label.setText(self.title)
        self._raw_frame = None
