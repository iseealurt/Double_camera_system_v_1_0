import os
import sys
import json
import shutil
from pathlib import Path

DATASET_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "datasheet", "PCB_DATASET"
)
IMAGES_DIR = os.path.join(DATASET_DIR, "images")
ANNOTATIONS_DIR = os.path.join(DATASET_DIR, "Annotations")
TRAIN_JSON = os.path.join(ANNOTATIONS_DIR, "train.json")
VAL_JSON = os.path.join(ANNOTATIONS_DIR, "val.json")

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "weights", "pcb_defect_det")
WEIGHTS_OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "weights", "pcb_defect_det.pt")

CLASS_NAMES = [
    "Mouse_bite",
    "Spur",
    "Missing_hole",
    "Short",
    "Open_circuit",
    "Spurious_copper",
]
NC = len(CLASS_NAMES)

EPOCHS = 100
BATCH_SIZE = 8
MODEL_SIZE = "n"
IMGSZ = 640


def convert_coco_to_yolo(coco_json_path, out_img_dir, out_label_dir):
    os.makedirs(out_img_dir, exist_ok=True)
    os.makedirs(out_label_dir, exist_ok=True)

    with open(coco_json_path, "r", encoding="utf-8") as f:
        coco = json.load(f)

    cat_names = {cat["id"]: cat["name"] for cat in coco["categories"]}

    image_map = {img["id"]: img for img in coco["images"]}

    anns_by_image = {}
    for ann in coco["annotations"]:
        img_id = ann["image_id"]
        if img_id not in anns_by_image:
            anns_by_image[img_id] = []
        anns_by_image[img_id].append(ann)

    converted = 0
    skipped = 0

    for img_id, img_info in image_map.items():
        fname = img_info["file_name"]
        img_w = img_info["width"]
        img_h = img_info["height"]

        src_path = os.path.join(IMAGES_DIR, fname)
        dst_img_path = os.path.join(out_img_dir, fname)

        if not os.path.exists(src_path):
            skipped += 1
            continue

        shutil.copy2(src_path, dst_img_path)

        anns = anns_by_image.get(img_id, [])

        label_lines = []
        for ann in anns:
            bbox = ann["bbox"]
            x, y, w, h = bbox
            xc = (x + w / 2.0) / img_w
            yc = (y + h / 2.0) / img_h
            nw = w / img_w
            nh = h / img_h

            category_id = ann["category_id"]
            if isinstance(category_id, str):
                try:
                    cls_id = int(category_id)
                except ValueError:
                    cls_id = category_id
            else:
                cls_id = category_id

            if isinstance(cls_id, str):
                try:
                    cls_id = CLASS_NAMES.index(cls_id)
                except ValueError:
                    cls_id = 0
            elif cls_id > NC - 1:
                cls_id = cls_id - 1

            label_lines.append(f"{cls_id} {xc:.6f} {yc:.6f} {nw:.6f} {nh:.6f}")

        stem = Path(fname).stem
        label_path = os.path.join(out_label_dir, f"{stem}.txt")
        with open(label_path, "w", encoding="utf-8") as f:
            f.write("\n".join(label_lines) + ("\n" if label_lines else ""))

        converted += 1

    return converted, skipped


def create_data_yaml(train_img_path, val_img_path, yaml_path):
    yaml_content = f"""path: {OUTPUT_DIR}
train: {train_img_path}
val: {val_img_path}

nc: {NC}
names: {json.dumps(CLASS_NAMES)}
"""
    os.makedirs(os.path.dirname(yaml_path), exist_ok=True)
    with open(yaml_path, "w", encoding="utf-8") as f:
        f.write(yaml_content)
    return yaml_path


def main():
    print("=" * 60)
    print("PCB Defect Detection Model Training")
    print("=" * 60)
    print()

    print("[Step 1/4] Converting COCO annotations to YOLO format...")

    train_img_dir = os.path.join(OUTPUT_DIR, "train", "images")
    train_label_dir = os.path.join(OUTPUT_DIR, "train", "labels")
    val_img_dir = os.path.join(OUTPUT_DIR, "val", "images")
    val_label_dir = os.path.join(OUTPUT_DIR, "val", "labels")

    if os.path.exists(OUTPUT_DIR):
        shutil.rmtree(OUTPUT_DIR)

    if not os.path.exists(TRAIN_JSON):
        print(f"[ERROR] Train annotation not found: {TRAIN_JSON}")
        sys.exit(1)
    if not os.path.exists(VAL_JSON):
        print(f"[ERROR] Val annotation not found: {VAL_JSON}")
        sys.exit(1)

    train_converted, train_skipped = convert_coco_to_yolo(TRAIN_JSON, train_img_dir, train_label_dir)
    print(f"  Train: {train_converted} images converted, {train_skipped} skipped")

    val_converted, val_skipped = convert_coco_to_yolo(VAL_JSON, val_img_dir, val_label_dir)
    print(f"  Val:   {val_converted} images converted, {val_skipped} skipped")
    print()

    print("[Step 2/4] Creating data.yaml...")
    data_yaml = create_data_yaml(train_img_dir, val_img_dir, os.path.join(OUTPUT_DIR, "data.yaml"))
    print(f"  Created: {data_yaml}")
    print()

    print("[Step 3/4] Loading YOLOv8 model...")
    from ultralytics import YOLO
    model_name = f"yolov8{MODEL_SIZE}.pt"
    print(f"  Base model: {model_name}")
    model = YOLO(model_name)
    print()

    print("[Step 4/4] Starting training...")
    print(f"  Classes: {NC} ({', '.join(CLASS_NAMES)})")
    print(f"  Epochs: {EPOCHS}")
    print(f"  Batch size: {BATCH_SIZE}")
    print(f"  Image size: {IMGSZ}")
    print(f"  Train images: {train_converted}")
    print(f"  Val images: {val_converted}")
    print()

    device = "cuda" if __import__("torch").cuda.is_available() else "cpu"
    print(f"  Device: {device}")
    print("  " + "-" * 50)

    results = model.train(
        data=data_yaml,
        epochs=EPOCHS,
        batch=BATCH_SIZE,
        imgsz=IMGSZ,
        device=device,
        project=os.path.dirname(WEIGHTS_OUTPUT),
        name=os.path.splitext(os.path.basename(WEIGHTS_OUTPUT))[0],
        exist_ok=True,
        verbose=True,
        patience=30,
        save=True,
        amp=True if device == "cuda" else False,
        lr0=0.01,
        lrf=0.01,
        momentum=0.937,
        weight_decay=0.0005,
        warmup_epochs=3.0,
        hsv_h=0.015,
        hsv_s=0.7,
        hsv_v=0.4,
        degrees=0.0,
        translate=0.1,
        scale=0.5,
        fliplr=0.5,
        mosaic=1.0,
        erasing=0.4,
    )

    best_pt = os.path.join(
        os.path.dirname(WEIGHTS_OUTPUT),
        os.path.splitext(os.path.basename(WEIGHTS_OUTPUT))[0],
        "weights",
        "best.pt",
    )

    if os.path.exists(best_pt):
        shutil.copy2(best_pt, WEIGHTS_OUTPUT)
        print(f"\n  Best model copied to: {WEIGHTS_OUTPUT}")

    print()
    print("=" * 60)
    print("Training Complete!")
    print(f"  Output model: {WEIGHTS_OUTPUT}")
    print("=" * 60)


if __name__ == "__main__":
    main()
