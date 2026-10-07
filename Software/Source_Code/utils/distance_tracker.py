import numpy as np
from collections import deque

from utils.config import STEREO_PARAMS


class DistanceTracker:
    def __init__(self, buffer_size=None, iou_threshold=0.3):
        if buffer_size is None:
            buffer_size = STEREO_PARAMS["FRAME_BUFFER_SIZE"]
        self.buffer_size = buffer_size
        self.iou_threshold = iou_threshold
        self._tracks = []

    @staticmethod
    def _compute_iou(bbox1, bbox2):
        x1 = max(bbox1[0], bbox2[0])
        y1 = max(bbox1[1], bbox2[1])
        x2 = min(bbox1[2], bbox2[2])
        y2 = min(bbox1[3], bbox2[3])
        if x2 < x1 or y2 < y1:
            return 0.0
        inter = (x2 - x1) * (y2 - y1)
        area1 = (bbox1[2] - bbox1[0]) * (bbox1[3] - bbox1[1])
        area2 = (bbox2[2] - bbox2[0]) * (bbox2[3] - bbox2[1])
        union = area1 + area2 - inter
        return inter / union if union > 0 else 0.0

    def _match(self, det):
        best_iou = 0.0
        best_idx = -1
        for i, track in enumerate(self._tracks):
            iou = self._compute_iou(det["bbox"], track["bbox"])
            if iou > best_iou:
                best_iou = iou
                best_idx = i
        if best_iou >= self.iou_threshold:
            return best_idx
        return -1

    def update(self, detections, raw_distances):
        matched_indices = set()
        tracked_distances = []

        for det, raw_dist in zip(detections, raw_distances):
            idx = self._match(det)
            if idx >= 0:
                matched_indices.add(idx)
                track = self._tracks[idx]
                track["bbox"] = det["bbox"]
                if raw_dist is not None:
                    track["distances"].append(raw_dist)
            else:
                track = {
                    "bbox": det["bbox"],
                    "class": det["class"],
                    "distances": deque(maxlen=self.buffer_size),
                }
                if raw_dist is not None:
                    track["distances"].append(raw_dist)
                self._tracks.append(track)
                idx = len(self._tracks) - 1
                matched_indices.add(idx)

            buf = list(self._tracks[idx]["distances"])
            if len(buf) > 0:
                tracked_distances.append(float(np.median(buf)))
            else:
                tracked_distances.append(None)

        self._tracks = [t for i, t in enumerate(self._tracks) if i in matched_indices]

        return tracked_distances

    def reset(self):
        self._tracks = []