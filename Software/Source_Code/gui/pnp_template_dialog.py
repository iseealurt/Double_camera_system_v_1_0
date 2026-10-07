import os
import cv2
import numpy as np
from PyQt5.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QPushButton, QLabel,
    QLineEdit, QFileDialog, QMessageBox, QGroupBox, QFormLayout,
    QProgressBar, QWidget, QFrame,
)
from PyQt5.QtGui import QPixmap, QImage, QFont
from PyQt5.QtCore import Qt

from utils.pnp_estimator import PnPProcessor
from utils import config


class PnPTemplateDialog(QDialog):
    TEMPLATE_STATE_IMAGE = 0
    TEMPLATE_STATE_SIZE = 1
    TEMPLATE_STATE_READY = 2

    def __init__(self, parent=None):
        super().__init__(parent)
        self.template_image = None
        self.template_path = None
        self.pcb_width_cm = 0.0
        self.pcb_height_cm = 0.0
        self.current_state = self.TEMPLATE_STATE_IMAGE
        self.processor = None

        self._init_ui()
        self._update_state()

    def _init_ui(self):
        self.setWindowTitle("PnP Template Registration")
        self.setMinimumSize(900, 700)
        self.setModal(True)

        main_layout = QVBoxLayout(self)
        header = QLabel("PnP Template Registration")
        header_font = QFont()
        header_font.setPointSize(14)
        header_font.setBold(True)
        header.setFont(header_font)
        header.setAlignment(Qt.AlignCenter)
        main_layout.addWidget(header)

        self.step_label = QLabel()
        self.step_label.setAlignment(Qt.AlignCenter)
        step_font = QFont()
        step_font.setPointSize(10)
        self.step_label.setFont(step_font)
        main_layout.addWidget(self.step_label)

        image_group = QGroupBox("Step 1: Select Template Image")
        image_layout = QVBoxLayout(image_group)

        btn_row = QHBoxLayout()
        self.select_btn = QPushButton("Browse Image...")
        self.select_btn.clicked.connect(self._on_select_image)
        btn_row.addWidget(self.select_btn)

        self.image_path_label = QLabel("No image selected")
        self.image_path_label.setStyleSheet("color: #888;")
        btn_row.addWidget(self.image_path_label, 1)
        image_layout.addLayout(btn_row)

        self.preview_label = QLabel()
        self.preview_label.setAlignment(Qt.AlignCenter)
        self.preview_label.setMinimumHeight(300)
        self.preview_label.setStyleSheet(
            "background-color: #1e1e1e; border: 1px solid #555;"
        )
        image_layout.addWidget(self.preview_label)
        main_layout.addWidget(image_group)

        size_group = QGroupBox("Step 2: PCB Physical Dimensions")
        size_layout = QFormLayout(size_group)

        self.width_input = QLineEdit()
        self.width_input.setPlaceholderText("e.g. 10.0")
        self.width_input.setEnabled(False)
        size_layout.addRow("Width (cm):", self.width_input)

        self.height_input = QLineEdit()
        self.height_input.setPlaceholderText("e.g. 8.0")
        self.height_input.setEnabled(False)
        size_layout.addRow("Height (cm):", self.height_input)

        main_layout.addWidget(size_group)

        self.progress_bar = QProgressBar()
        self.progress_bar.setVisible(False)
        main_layout.addWidget(self.progress_bar)

        self.status_label = QLabel()
        self.status_label.setAlignment(Qt.AlignCenter)
        self.status_label.setStyleSheet("color: #ffaa00; font-weight: bold;")
        main_layout.addWidget(self.status_label)

        btn_layout = QHBoxLayout()
        self.confirm_img_btn = QPushButton("Confirm Image")
        self.confirm_img_btn.setEnabled(False)
        self.confirm_img_btn.clicked.connect(self._on_confirm_image)
        btn_layout.addWidget(self.confirm_img_btn)

        self.confirm_size_btn = QPushButton("Confirm Size")
        self.confirm_size_btn.setEnabled(False)
        self.confirm_size_btn.clicked.connect(self._on_confirm_size)
        btn_layout.addWidget(self.confirm_size_btn)

        self.process_btn = QPushButton("Process Template")
        self.process_btn.setEnabled(False)
        self.process_btn.clicked.connect(self._on_process_template)
        btn_layout.addWidget(self.process_btn)

        self.finish_btn = QPushButton("Finish")
        self.finish_btn.setEnabled(False)
        self.finish_btn.clicked.connect(self.accept)
        btn_layout.addWidget(self.finish_btn)

        main_layout.addLayout(btn_layout)

    def _update_state(self):
        img_loaded = self.template_image is not None
        size_loaded = self.pcb_width_cm > 0 and self.pcb_height_cm > 0

        if not img_loaded:
            self.current_state = self.TEMPLATE_STATE_IMAGE
            self.step_label.setText(
                'Status: <span style="color:#ffaa00;">Please select a PCB template image</span>'
            )
            self.confirm_img_btn.setEnabled(False)
            self.width_input.setEnabled(False)
            self.height_input.setEnabled(False)
            self.confirm_size_btn.setEnabled(False)
            self.process_btn.setEnabled(False)
            self.finish_btn.setEnabled(False)
            self.status_label.setText("")
        elif not size_loaded:
            self.current_state = self.TEMPLATE_STATE_SIZE
            self.step_label.setText(
                'Status: <span style="color:#00aaff;">Template image cached. Please enter PCB dimensions.</span>'
            )
            self.confirm_img_btn.setEnabled(False)
            self.width_input.setEnabled(True)
            self.height_input.setEnabled(True)
            self.confirm_size_btn.setEnabled(True)
            self.process_btn.setEnabled(False)
            self.finish_btn.setEnabled(False)
            self.status_label.setText(
                "Template image cached. Please enter PCB dimensions."
            )
            self.status_label.setStyleSheet("color: #00aaff; font-weight: bold;")
        else:
            self.current_state = self.TEMPLATE_STATE_READY
            self.step_label.setText(
                'Status: <span style="color:#00ff00;">PCB dimensions cached. Click Process to complete template registration.</span>'
            )
            self.confirm_img_btn.setEnabled(False)
            self.width_input.setEnabled(False)
            self.height_input.setEnabled(False)
            self.confirm_size_btn.setEnabled(False)
            self.process_btn.setEnabled(True)
            self.finish_btn.setEnabled(False)
            self.status_label.setText(
                "PCB dimensions cached. Please click 'Process Template' to complete."
            )
            self.status_label.setStyleSheet("color: #00ff00; font-weight: bold;")

    def _on_select_image(self):
        file_path, _ = QFileDialog.getOpenFileName(
            self,
            "Select PCB Template Image",
            "",
            "Image Files (*.png *.jpg *.jpeg *.bmp *.tif *.tiff);;All Files (*)",
        )
        if not file_path:
            return

        self.template_path = file_path
        self.image_path_label.setText(os.path.basename(file_path))
        self.image_path_label.setStyleSheet("color: #fff;")

        img = cv2.imdecode(
            np.fromfile(file_path, dtype=np.uint8), cv2.IMREAD_COLOR
        )
        if img is None:
            QMessageBox.critical(
                self, "Error", f"Failed to load image:\n{file_path}"
            )
            return

        self.template_image = img.copy()

        h, w, ch = img.shape
        max_display_w = 640
        scale = min(max_display_w / w, 400 / h)
        display_w = int(w * scale)
        display_h = int(h * scale)

        rgb_img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        resized = cv2.resize(rgb_img, (display_w, display_h))
        bytes_per_line = display_w * 3
        q_img = QImage(
            resized.data, display_w, display_h, bytes_per_line, QImage.Format_RGB888
        )
        self.preview_label.setPixmap(
            QPixmap.fromImage(q_img)
        )

        self.confirm_img_btn.setEnabled(True)
        self.status_label.setText("Image loaded. Click 'Confirm Image' to cache it.")

    def _on_confirm_image(self):
        if self.template_image is None:
            return

        QMessageBox.information(
            self,
            "Template Cached",
            "Template image has been cached. Please enter PCB dimensions.",
        )
        self._update_state()

    def _on_confirm_size(self):
        try:
            w = float(self.width_input.text().strip())
            h = float(self.height_input.text().strip())
        except ValueError:
            QMessageBox.warning(
                self, "Invalid Input",
                "Please enter valid numeric values for width and height.",
            )
            return

        if w <= 0 or h <= 0:
            QMessageBox.warning(
                self, "Invalid Input",
                "Width and height must be positive numbers.",
            )
            return

        self.pcb_width_cm = w
        self.pcb_height_cm = h

        QMessageBox.information(
            self,
            "Dimensions Cached",
            "PCB dimensions have been cached.\n"
            "Please click 'Process Template' to complete template registration.",
        )
        self._update_state()

    def _on_process_template(self):
        if self.template_image is None or self.pcb_width_cm <= 0 or self.pcb_height_cm <= 0:
            return

        self.progress_bar.setVisible(True)
        self.progress_bar.setValue(10)
        self.process_btn.setEnabled(False)
        self.status_label.setText("Processing template...")
        self.status_label.setStyleSheet("color: #ffaa00; font-weight: bold;")

        from PyQt5.QtCore import QCoreApplication
        QCoreApplication.processEvents()

        self.processor = PnPProcessor()
        self.processor.set_template(
            self.template_image, self.pcb_width_cm, self.pcb_height_cm
        )

        self.progress_bar.setValue(50)
        QCoreApplication.processEvents()

        if self.processor.template_des is not None:
            n_keypoints = len(self.processor.template_kp)
            self.progress_bar.setValue(100)

            self.status_label.setText(
                f"Template processed successfully! "
                f"Extracted {n_keypoints} ORB features."
            )
            self.status_label.setStyleSheet("color: #00ff00; font-weight: bold;")

            QMessageBox.information(
                self,
                "Template Ready",
                f"Template registration complete!\n\n"
                f"PCB Size: {self.pcb_width_cm} x {self.pcb_height_cm} cm\n"
                f"3D Model Points: 4 corners (for PnP solving)\n"
                f"ORB Features: {n_keypoints} keypoints extracted\n\n"
                "The system is now ready for PnP pose estimation.",
            )

            self.finish_btn.setEnabled(True)
            self.process_btn.setEnabled(False)
        else:
            self.progress_bar.setValue(0)
            self.status_label.setText(
                "Failed to extract features from template image. Please try another image."
            )
            self.status_label.setStyleSheet("color: #ff0000; font-weight: bold;")
            self.process_btn.setEnabled(True)
            QMessageBox.critical(
                self, "Processing Failed",
                "Could not extract ORB features from the template image.\n"
                "Please select a different image with more texture.",
            )

    def get_processor(self):
        return self.processor

    def get_template_info(self):
        if self.processor is not None and self.processor.template_loaded:
            return {
                "width_cm": self.pcb_width_cm,
                "height_cm": self.pcb_height_cm,
                "n_features": len(self.processor.template_kp)
                if self.processor.template_kp
                else 0,
            }
        return None
