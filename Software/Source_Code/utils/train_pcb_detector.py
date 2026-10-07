import os
import sys
import argparse
import shutil
import glob
import zipfile
import urllib.request
import numpy as np
from pathlib import Path


DATASET_URLS = {
    "baidu_aistudio": "https://aistudio.baidu.com/datasetdetail/297149",
}

EXPECTED_CLASSES = [
    "Mouse_bite", "Spur", "Missing_hole",
    "Short", "Open_circuit", "Spurious_copper",
]


def download_dataset(target_dir):
    print("=" * 60)
    print("PKU-Market-PCB dataset download")
    print("=" * 60)
    print()
    print("The PKU-Market-PCB dataset is NOT bundled with this script.")
    print("Please download it manually from one of the following sources:")
    print()
    print(f"  1. Baidu AI Studio (YOLO format, recommended):")
    print(f"     {DATASET_URLS['baidu_aistudio']}")
    print()
    print("  2. Official PKU page (VOC format):")
    print("     https://robotics.pkusz.edu.cn/resources/dataset/")
    print()
    print("After downloading, extract the zip file and provide the")
    print("extracted directory path via --data_dir.")
    print()
    print("Expected YOLO format structure:")
    print("  <data_dir>/")
    print("    images/")
    print("      train/  (or all images here)")
    print("      val/")
    print("    labels/")
    print("      train/  (or all labels here)")
    print("      val/")
    print()
    print("Each label file (*.txt) contains lines:")
    print("  class_id x_center y_center width height")
    print("  where class_id 0-5 corresponds to:")
    for i, name in enumerate(EXPECTED_CLASSES):
        print(f"    {i}: {name}")
    print()
    print("=" * 60)
    return False


def parse_yolo_label(label_path, img_w, img_h):
    boxes = []
    if not os.path.exists(label_path):
        return boxes
    with open(label_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 5:
                continue
            cls_id = int(parts[0])
            xc = float(parts[1]) * img_w
            yc = float(parts[2]) * img_h
            bw = float(parts[3]) * img_w
            bh = float(parts[4]) * img_h
            x1 = xc - bw / 2
            y1 = yc - bh / 2
            x2 = xc + bw / 2
            y2 = yc + bh / 2
            boxes.append((cls_id, x1, y1, x2, y2))
    return boxes


def compute_pcb_bbox(boxes, img_w, img_h, padding_ratio=0.05):
    if not boxes:
        return None
    x1 = min(b[1] for b in boxes)
    y1 = min(b[2] for b in boxes)
    x2 = max(b[3] for b in boxes)
    y2 = max(b[4] for b in boxes)

    pad_w = (x2 - x1) * padding_ratio
    pad_h = (y2 - y1) * padding_ratio
    x1 = max(0, x1 - pad_w)
    y1 = max(0, y1 - pad_h)
    x2 = min(img_w, x2 + pad_w)
    y2 = min(img_h, y2 + pad_h)

    if x2 <= x1 or y2 <= y1:
        return None
    return (x1, y1, x2, y2)


def convert_dataset(data_dir, output_dir, padding_ratio=0.05):
    image_extensions = ('.jpg', '.jpeg', '.png', '.bmp')

    splits = []

    train_img_dir = os.path.join(data_dir, 'images', 'train')
    val_img_dir = os.path.join(data_dir, 'images', 'val')

    if os.path.exists(train_img_dir):
        splits.append(('train', train_img_dir))
    if os.path.exists(val_img_dir):
        splits.append(('val', val_img_dir))

    if not splits:
        all_img_dir = os.path.join(data_dir, 'images')
        if os.path.exists(all_img_dir):
            splits.append(('all', all_img_dir))

    if not splits:
        print("ERROR: No images directory found in", data_dir)
        print("Expected structure: <data_dir>/images/train/ or <data_dir>/images/")
        return False

    os.makedirs(output_dir, exist_ok=True)
    out_img_dir = os.path.join(output_dir, 'images')
    out_label_dir = os.path.join(output_dir, 'labels')
    os.makedirs(out_img_dir, exist_ok=True)
    os.makedirs(out_label_dir, exist_ok=True)

    total_converted = 0
    total_skipped = 0

    for split_name, img_dir in splits:
        label_dir = img_dir.replace('images', 'labels')
        if not os.path.exists(label_dir):
            print(f"  WARNING: Labels directory not found: {label_dir}")
            continue

        out_split_img = os.path.join(out_img_dir, split_name)
        out_split_label = os.path.join(out_label_dir, split_name)
        os.makedirs(out_split_img, exist_ok=True)
        os.makedirs(out_split_label, exist_ok=True)

        image_files = []
        for ext in image_extensions:
            image_files.extend(glob.glob(os.path.join(img_dir, f'*{ext}')))
            image_files.extend(glob.glob(os.path.join(img_dir, f'*{ext.upper()}')))

        print(f"Processing {split_name} set: {len(image_files)} images...")

        for img_path in image_files:
            stem = Path(img_path).stem
            label_path = os.path.join(label_dir, f'{stem}.txt')

            if not os.path.exists(label_path):
                total_skipped += 1
                continue

            import cv2
            img = cv2.imread(img_path)
            if img is None:
                total_skipped += 1
                continue
            img_h, img_w = img.shape[:2]

            boxes = parse_yolo_label(label_path, img_w, img_h)
            if not boxes:
                total_skipped += 1
                continue

            pcb_bbox = compute_pcb_bbox(boxes, img_w, img_h, padding_ratio)
            if pcb_bbox is None:
                total_skipped += 1
                continue

            x1, y1, x2, y2 = pcb_bbox
            xc = (x1 + x2) / 2.0 / img_w
            yc = (y1 + y2) / 2.0 / img_h
            bw = (x2 - x1) / img_w
            bh = (y2 - y1) / img_h

            shutil.copy2(img_path, os.path.join(out_split_img, f'{stem}.jpg'))

            out_label_path = os.path.join(out_split_label, f'{stem}.txt')
            with open(out_label_path, 'w') as f:
                f.write(f"0 {xc:.6f} {yc:.6f} {bw:.6f} {bh:.6f}\n")

            total_converted += 1

    print(f"\nConversion complete: {total_converted} images, {total_skipped} skipped")
    return total_converted > 0


def create_data_yaml(output_dir):
    yaml_path = os.path.join(output_dir, 'pcb_dataset.yaml')

    train_img_dir = os.path.join(output_dir, 'images', 'train')
    val_img_dir = os.path.join(output_dir, 'images', 'val')
    all_img_dir = os.path.join(output_dir, 'images', 'all')

    if os.path.exists(train_img_dir):
        train_path = os.path.abspath(train_img_dir)
    elif os.path.exists(all_img_dir):
        train_path = os.path.abspath(all_img_dir)
    else:
        train_path = os.path.abspath(os.path.join(output_dir, 'images'))

    if os.path.exists(val_img_dir):
        val_path = os.path.abspath(val_img_dir)
    else:
        val_path = train_path

    yaml_content = f"""train: {train_path}
val: {val_path}

nc: 1
names: ['PCB']
"""
    with open(yaml_path, 'w') as f:
        f.write(yaml_content)

    print(f"Created dataset config: {yaml_path}")
    return yaml_path


def train_model(data_yaml, output_weights, epochs, batch_size, model_size):
    print("\n" + "=" * 60)
    print("Starting YOLOv8 training for PCB board detection")
    print("=" * 60)

    from ultralytics import YOLO

    model_name = f"yolov8{model_size}.pt"
    print(f"Loading base model: {model_name}")
    model = YOLO(model_name)

    print(f"Training for {epochs} epochs, batch_size={batch_size}...")
    results = model.train(
        data=data_yaml,
        epochs=epochs,
        batch=batch_size,
        imgsz=640,
        device='cuda' if __import__('torch').cuda.is_available() else 'cpu',
        project=os.path.dirname(output_weights),
        name=os.path.splitext(os.path.basename(output_weights))[0],
        exist_ok=True,
        verbose=True,
        patience=30,
        save=True,
        amp=True,
    )

    best_pt = os.path.join(
        os.path.dirname(output_weights),
        os.path.splitext(os.path.basename(output_weights))[0],
        'weights',
        'best.pt',
    )

    if os.path.exists(best_pt):
        shutil.copy2(best_pt, output_weights)
        print(f"\nBest model saved to: {output_weights}")
    else:
        print(f"\nWARNING: best.pt not found at {best_pt}")
        print(f"Training output may be in: {os.path.dirname(output_weights)}")

    return output_weights


def main():
    parser = argparse.ArgumentParser(
        description="Train a PCB board-level YOLOv8 detector from PKU-Market-PCB dataset"
    )
    parser.add_argument(
        "--data_dir", type=str, default=None,
        help="Path to PKU-Market-PCB dataset (YOLO format)"
    )
    parser.add_argument(
        "--output_dir", type=str, default=None,
        help="Output directory for converted PCB board dataset"
    )
    parser.add_argument(
        "--weights", type=str, default=None,
        help="Output path for trained model weights"
    )
    parser.add_argument(
        "--epochs", type=int, default=50,
        help="Number of training epochs (default: 50)"
    )
    parser.add_argument(
        "--batch", type=int, default=8,
        help="Batch size (default: 8)"
    )
    parser.add_argument(
        "--model_size", type=str, default='n',
        choices=['n', 's', 'm', 'l', 'x'],
        help="YOLOv8 model size: n=sano, s=small, m=medium, l=large, x=xlarge (default: n)"
    )
    parser.add_argument(
        "--padding", type=float, default=0.05,
        help="Padding ratio around defect bboxes for PCB bbox (default: 0.05)"
    )
    parser.add_argument(
        "--download_only", action='store_true',
        help="Only show download instructions, don't train"
    )

    args = parser.parse_args()

    if args.download_only:
        download_dataset(None)
        return

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)

    if args.weights is None:
        default_weights_dir = os.path.join(project_root, 'weights')
        os.makedirs(default_weights_dir, exist_ok=True)
        args.weights = os.path.join(default_weights_dir, 'pcb_board_det.pt')

    if args.data_dir is None:
        print("ERROR: --data_dir is required.")
        print("Please download the PKU-Market-PCB dataset first.")
        print("Run with --download_only for instructions.")
        sys.exit(1)

    if not os.path.exists(args.data_dir):
        print(f"ERROR: Data directory not found: {args.data_dir}")
        sys.exit(1)

    if args.output_dir is None:
        args.output_dir = os.path.join(
            os.path.dirname(args.data_dir),
            'pcb_board_dataset'
        )

    print("Step 1: Converting defect annotations to PCB board-level annotations...")
    success = convert_dataset(args.data_dir, args.output_dir, args.padding)
    if not success:
        print("ERROR: Dataset conversion failed. No valid images found.")
        sys.exit(1)

    print("\nStep 2: Creating dataset YAML configuration...")
    data_yaml = create_data_yaml(args.output_dir)

    print("\nStep 3: Training YOLOv8 PCB board detector...")
    result = train_model(data_yaml, args.weights, args.epochs, args.batch, args.model_size)

    print("\n" + "=" * 60)
    print("Training complete!")
    print(f"Model saved to: {result}")
    print("You can now use this model with pcb_board_detector.py")
    print("=" * 60)


if __name__ == '__main__':
    main()
