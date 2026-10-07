import os
import numpy as np
import torch

from utils.config import (
    PCB_BOARD_MODEL_WEIGHTS_PATH,
    PCB_BOARD_CONF_THRESHOLD,
    PCB_BOARD_IOU_THRESHOLD,
)


class PCBBoardDetector:
    def __init__(self):
        self._model = None
        self._device = None
        self._loaded = False

    @property
    def is_loaded(self):
        return self._loaded

    def load(self, weights_path=None):
        if self._loaded:
            return True

        if weights_path is None:
            weights_path = PCB_BOARD_MODEL_WEIGHTS_PATH

        if not os.path.exists(weights_path):
            raise FileNotFoundError(
                f"PCB board detector weights not found at: {weights_path}\n"
                f"Please run train_pcb_detector.py to train the model first."
            )

        from ultralytics import YOLO

        self._device = 'cuda' if torch.cuda.is_available() else 'cpu'
        self._model = YOLO(weights_path)
        self._loaded = True
        print(f"[PCBBoardDetector] Loaded model from: {weights_path} (device: {self._device})")
        return True

    def detect(self, image, conf_threshold=None, iou_threshold=None):
        if not self._loaded:
            raise RuntimeError("PCBBoardDetector not loaded. Call load() first.")

        if conf_threshold is None:
            conf_threshold = PCB_BOARD_CONF_THRESHOLD
        if iou_threshold is None:
            iou_threshold = PCB_BOARD_IOU_THRESHOLD

        results = self._model(
            image,
            conf=conf_threshold,
            iou=iou_threshold,
            device=self._device,
            verbose=False,
        )

        detections = []
        if len(results) > 0 and results[0].boxes is not None:
            boxes = results[0].boxes.xyxy.cpu().numpy()
            confs = results[0].boxes.conf.cpu().numpy()
            cls_ids = results[0].boxes.cls.cpu().numpy().astype(int)

            for i in range(len(boxes)):
                detections.append({
                    'bbox': boxes[i].astype(int),
                    'confidence': float(confs[i]),
                    'class_id': int(cls_ids[i]),
                    'class_name': 'PCB',
                })

        return detections

    def detect_best(self, image, conf_threshold=None, iou_threshold=None):
        detections = self.detect(image, conf_threshold, iou_threshold)
        if not detections:
            return None
        return max(detections, key=lambda d: d['confidence'])

    def unload(self):
        self._model = None
        self._loaded = False
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        print("[PCBBoardDetector] Model unloaded, GPU memory cleared")
