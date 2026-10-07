import cv2
import numpy as np
import torch

from ultralytics import YOLO


CLASS_NAMES = [
    "Mouse_bite",
    "Spur",
    "Missing_hole",
    "Short",
    "Open_circuit",
    "Spurious_copper",
]

CLASS_COLORS = {
    "Mouse_bite": (0, 255, 0),
    "Spur": (255, 80, 80),
    "Missing_hole": (80, 80, 255),
    "Short": (255, 255, 0),
    "Open_circuit": (255, 80, 255),
    "Spurious_copper": (80, 255, 255),
}

MODEL_INPUT_SIZE = 640
DEFAULT_CONF_THRESHOLD = 0.25
DEFAULT_IOU_THRESHOLD = 0.45
DEFAULT_INFERENCE_SKIP = 1


class PCBDetector:
    def __init__(self, weights_path):
        self.weights_path = weights_path
        self.model = None
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self._frame_count = 0
        self.inference_skip = DEFAULT_INFERENCE_SKIP

    def load(self):
        self.model = YOLO(self.weights_path)
        self.model.to(self.device)
        return self.device

    def detect(self, image, conf_threshold=None, iou_threshold=None):
        if self.model is None:
            return []

        if conf_threshold is None:
            conf_threshold = DEFAULT_CONF_THRESHOLD
        if iou_threshold is None:
            iou_threshold = DEFAULT_IOU_THRESHOLD

        self._frame_count += 1
        if self._frame_count % self.inference_skip != 0:
            return self._last_detections if hasattr(self, '_last_detections') else []

        input_img = cv2.resize(image, (MODEL_INPUT_SIZE, MODEL_INPUT_SIZE))

        results = self.model(
            input_img,
            conf=conf_threshold,
            iou=iou_threshold,
            verbose=False,
            device=self.device,
        )

        detections = []
        if len(results) > 0 and results[0].boxes is not None:
            boxes = results[0].boxes
            img_h, img_w = image.shape[:2]
            scale_x = img_w / MODEL_INPUT_SIZE
            scale_y = img_h / MODEL_INPUT_SIZE

            for i in range(len(boxes)):
                xyxy = boxes.xyxy[i].cpu().numpy()
                cls_id = int(boxes.cls[i].item())
                conf = float(boxes.conf[i].item())

                x1 = max(0, int(xyxy[0] * scale_x))
                y1 = max(0, int(xyxy[1] * scale_y))
                x2 = min(img_w, int(xyxy[2] * scale_x))
                y2 = min(img_h, int(xyxy[3] * scale_y))

                class_name = (
                    CLASS_NAMES[cls_id]
                    if cls_id < len(CLASS_NAMES)
                    else f"class_{cls_id}"
                )

                detections.append({
                    "bbox": (x1, y1, x2, y2),
                    "class": class_name,
                    "conf": conf,
                })

        self._last_detections = detections
        return detections

    def unload(self):
        if self.model is not None:
            del self.model
            self.model = None
            if self.device == "cuda":
                torch.cuda.empty_cache()
