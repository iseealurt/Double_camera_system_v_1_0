import os
import sys
import time
from pathlib import Path
from datetime import datetime

import cv2
import numpy as np
from ultralytics import YOLO

MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "weights", "pcb_defect_det.pt")
DATASET_IMAGES_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "datasheet", "PCB_DATASET", "images"
)
REPORT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "AI"
)
REPORT_PATH = os.path.join(REPORT_DIR, "report.md")
INPUT_SIZE = 640
CONF_THRESHOLD = 0.25
IOU_THRESHOLD = 0.45

CLASS_NAMES = {
    0: "Mouse_bite",
    1: "Spur",
    2: "Missing_hole",
    3: "Short",
    4: "Open_circuit",
    5: "Spurious_copper",
}

IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff")


def collect_images(root_dir):
    image_paths = []
    for fname in sorted(os.listdir(root_dir)):
        fpath = os.path.join(root_dir, fname)
        if os.path.isfile(fpath) and fname.lower().endswith(IMAGE_EXTENSIONS):
            image_paths.append(fpath)
    return image_paths


def resize_to_input(image, target_size):
    h, w = image.shape[:2]
    if h == target_size and w == target_size:
        return image
    return cv2.resize(image, (target_size, target_size), interpolation=cv2.INTER_LINEAR)


def preprocess_image(image):
    h, w = image.shape[:2]
    resized = resize_to_input(image, INPUT_SIZE)
    return resized, (w, h)


def run_inference(model, image_paths):
    all_results = []
    total = len(image_paths)
    start_time = time.time()

    for idx, img_path in enumerate(image_paths):
        image = cv2.imread(img_path)
        if image is None:
            print(f"  [SKIP] Cannot read: {os.path.basename(img_path)}")
            all_results.append({
                "filename": os.path.basename(img_path),
                "status": "read_error",
                "original_size": None,
                "detections": [],
                "inference_time_ms": 0,
            })
            continue

        original_h, original_w = image.shape[:2]
        resized, original_dims = preprocess_image(image)

        t0 = time.perf_counter()
        results = model(
            resized,
            conf=CONF_THRESHOLD,
            iou=IOU_THRESHOLD,
            verbose=False,
        )
        t1 = time.perf_counter()
        elapsed_ms = (t1 - t0) * 1000

        detections = []
        if len(results) > 0 and results[0].boxes is not None:
            boxes = results[0].boxes.xyxy.cpu().numpy()
            confs = results[0].boxes.conf.cpu().numpy()
            cls_ids = results[0].boxes.cls.cpu().numpy().astype(int)

            scale_x = original_w / INPUT_SIZE
            scale_y = original_h / INPUT_SIZE

            for i in range(len(boxes)):
                x1 = int(boxes[i][0] * scale_x)
                y1 = int(boxes[i][1] * scale_y)
                x2 = int(boxes[i][2] * scale_x)
                y2 = int(boxes[i][3] * scale_y)
                detections.append({
                    "bbox": [x1, y1, x2, y2],
                    "confidence": round(float(confs[i]), 4),
                    "class_id": int(cls_ids[i]),
                    "class_name": CLASS_NAMES.get(int(cls_ids[i]), f"class_{cls_ids[i]}"),
                })

        all_results.append({
            "filename": os.path.basename(img_path),
            "original_size": f"{original_w}x{original_h}",
            "status": "ok",
            "detections": detections,
            "inference_time_ms": round(elapsed_ms, 2),
        })

        pct = (idx + 1) / total * 100
        bar_len = 40
        filled = int(bar_len * (idx + 1) / total)
        bar = "#" * filled + "-" * (bar_len - filled)
        print(f"\r  [{bar}] {pct:.1f}% ({idx + 1}/{total})", end="", flush=True)

    print()
    elapsed_total = time.time() - start_time
    return all_results, elapsed_total


def compute_statistics(results):
    total_images = len(results)
    ok_images = [r for r in results if r["status"] == "ok"]
    error_images = [r for r in results if r["status"] != "ok"]

    total_detections = sum(len(r["detections"]) for r in ok_images)
    images_with_detections = sum(1 for r in ok_images if len(r["detections"]) > 0)
    all_confs = []
    class_counts = {}
    for r in ok_images:
        for d in r["detections"]:
            all_confs.append(d["confidence"])
            cls_name = d["class_name"]
            class_counts[cls_name] = class_counts.get(cls_name, 0) + 1

    all_times = [r["inference_time_ms"] for r in ok_images]

    return {
        "total_images": total_images,
        "ok_images": len(ok_images),
        "error_images": len(error_images),
        "total_detections": total_detections,
        "images_with_detections": images_with_detections,
        "detection_rate": round(images_with_detections / len(ok_images) * 100, 2) if ok_images else 0,
        "avg_detections_per_image": round(total_detections / len(ok_images), 2) if ok_images else 0,
        "class_counts": class_counts,
        "avg_confidence": round(np.mean(all_confs), 4) if all_confs else 0,
        "min_confidence": round(np.min(all_confs), 4) if all_confs else 0,
        "max_confidence": round(np.max(all_confs), 4) if all_confs else 0,
        "avg_inference_time_ms": round(np.mean(all_times), 2) if all_times else 0,
        "min_inference_time_ms": round(np.min(all_times), 2) if all_times else 0,
        "max_inference_time_ms": round(np.max(all_times), 2) if all_times else 0,
        "total_inference_time_ms": round(sum(all_times), 2),
    }


def generate_report(results, stats, total_time_s):
    os.makedirs(REPORT_DIR, exist_ok=True)

    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    lines = []
    lines.append("# PCB Defect Detection Model Test Report")
    lines.append("")
    lines.append(f"> Generated: {now_str}")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 1. Test Configuration")
    lines.append("")
    lines.append("| Item | Value |")
    lines.append("|------|-------|")
    lines.append(f"| Model | `{os.path.basename(MODEL_PATH)}` |")
    lines.append(f"| Input Size | {INPUT_SIZE} x {INPUT_SIZE} |")
    lines.append(f"| Confidence Threshold | {CONF_THRESHOLD} |")
    lines.append(f"| IoU Threshold | {IOU_THRESHOLD} |")
    lines.append(f"| Dataset | `PCB_DATASET/images/` |")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 2. Overall Statistics")
    lines.append("")
    lines.append("| Metric | Value |")
    lines.append("|--------|-------|")
    lines.append(f"| Total images tested | {stats['total_images']} |")
    lines.append(f"| Successfully processed | {stats['ok_images']} |")
    lines.append(f"| Read errors | {stats['error_images']} |")
    lines.append(f"| Total detections | {stats['total_detections']} |")
    lines.append(f"| Images with detections | {stats['images_with_detections']} |")
    lines.append(f"| Detection rate | {stats['detection_rate']}% |")
    lines.append(f"| Avg detections per image | {stats['avg_detections_per_image']} |")
    lines.append("")
    lines.append("### Confidence Distribution")
    lines.append("")
    lines.append("| Metric | Value |")
    lines.append("|--------|-------|")
    lines.append(f"| Average confidence | {stats['avg_confidence']} |")
    lines.append(f"| Min confidence | {stats['min_confidence']} |")
    lines.append(f"| Max confidence | {stats['max_confidence']} |")
    lines.append("")
    lines.append("### Inference Time")
    lines.append("")
    lines.append("| Metric | Value |")
    lines.append("|--------|-------|")
    lines.append(f"| Average (ms) | {stats['avg_inference_time_ms']} |")
    lines.append(f"| Min (ms) | {stats['min_inference_time_ms']} |")
    lines.append(f"| Max (ms) | {stats['max_inference_time_ms']} |")
    lines.append(f"| Total (ms) | {stats['total_inference_time_ms']} |")
    lines.append(f"| Wall clock (s) | {round(total_time_s, 2)} |")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 3. Per-Class Detection Summary")
    lines.append("")
    if stats["class_counts"]:
        lines.append("| Class | Count |")
        lines.append("|-------|-------|")
        for cls_name in sorted(stats["class_counts"].keys()):
            lines.append(f"| {cls_name} | {stats['class_counts'][cls_name]} |")
    else:
        lines.append("No detections across all classes.")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 4. Per-Image Detection Details")
    lines.append("")

    for r in results:
        fname = r["filename"]
        status = r["status"]
        orig_size = r["original_size"]
        dets = r["detections"]
        t_ms = r["inference_time_ms"]

        if status != "ok":
            lines.append(f"### `{fname}`")
            lines.append("")
            lines.append(f"- **Status**: ERROR (cannot read)")
            lines.append("")
            continue

        lines.append(f"### `{fname}`")
        lines.append("")
        lines.append(f"- **Original size**: {orig_size}")
        lines.append(f"- **Inference time**: {t_ms} ms")
        lines.append(f"- **Detections**: {len(dets)}")
        lines.append("")

        if dets:
            lines.append("| # | Class | Confidence | BBox (x1, y1, x2, y2) |")
            lines.append("|---|-------|------------|--------------------------|")
            for i, d in enumerate(dets, 1):
                bbox_str = f"({d['bbox'][0]}, {d['bbox'][1]}, {d['bbox'][2]}, {d['bbox'][3]})"
                lines.append(f"| {i} | {d['class_name']} | {d['confidence']} | {bbox_str} |")
            lines.append("")

    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    return REPORT_PATH


def main():
    print("=" * 60)
    print("PCB Defect Detection Model Test")
    print("=" * 60)
    print()

    if not os.path.exists(MODEL_PATH):
        print(f"[ERROR] Model not found: {MODEL_PATH}")
        sys.exit(1)

    if not os.path.exists(DATASET_IMAGES_DIR):
        print(f"[ERROR] Dataset images directory not found: {DATASET_IMAGES_DIR}")
        sys.exit(1)

    print(f"Model:  {MODEL_PATH}")
    print(f"Images: {DATASET_IMAGES_DIR}")
    print(f"Report: {REPORT_PATH}")
    print()

    print("[1/4] Loading model...")
    model = YOLO(MODEL_PATH)
    print("      Model loaded successfully.")
    print()

    print("[2/4] Collecting images...")
    image_paths = collect_images(DATASET_IMAGES_DIR)
    print(f"      Found {len(image_paths)} images.")
    print()

    print("[3/4] Running inference...")
    results, total_time = run_inference(model, image_paths)
    print(f"      Completed in {total_time:.2f}s")
    print()

    print("[4/4] Generating report...")
    stats = compute_statistics(results)
    report_path = generate_report(results, stats, total_time)
    print(f"      Report saved to: {report_path}")
    print()

    print("=" * 60)
    print("Test Summary")
    print("=" * 60)
    print(f"  Images tested:         {stats['total_images']}")
    print(f"  Total detections:      {stats['total_detections']}")
    print(f"  Detection rate:        {stats['detection_rate']}%")
    print(f"  Avg confidence:        {stats['avg_confidence']}")
    print(f"  Avg inference time:    {stats['avg_inference_time_ms']} ms")
    print("=" * 60)


if __name__ == "__main__":
    main()
