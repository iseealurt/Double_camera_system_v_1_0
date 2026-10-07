import os
import csv
import json
import sys
from datetime import datetime

from ultralytics import YOLO

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TRAIN_DIR = os.path.join(SCRIPT_DIR, "weights", "pcb_defect_det")
BEST_PT = os.path.join(TRAIN_DIR, "weights", "best.pt")
RESULTS_CSV = os.path.join(TRAIN_DIR, "results.csv")
DATA_YAML = os.path.join(TRAIN_DIR, "data.yaml")

PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
REPORT_DIR = os.path.join(PROJECT_ROOT, "AI")
REPORT_PATH = os.path.join(REPORT_DIR, "report.md")

CLASS_NAMES = [
    "Mouse_bite", "Spur", "Missing_hole",
    "Short", "Open_circuit", "Spurious_copper",
]


def parse_results_csv(csv_path):
    rows = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append(row)
    return rows


def run_validation(model_path, data_yaml):
    model = YOLO(model_path)
    results = model.val(data=data_yaml, verbose=False, split="val")
    return results


def generate_report():
    print("=" * 60)
    print("Generating Training Validation Report")
    print("=" * 60)
    print()

    print("[1/3] Loading best model and running validation...")
    val_results = run_validation(BEST_PT, DATA_YAML)
    print(f"      Validation complete: mAP50={val_results.box.map50:.4f}, mAP50-95={val_results.box.map:.4f}")
    print()

    print("[2/3] Parsing training history...")
    csv_rows = parse_results_csv(RESULTS_CSV)
    total_epochs = len(csv_rows)
    last_row = csv_rows[-1]
    best_mAP50 = max(float(r["metrics/mAP50(B)"]) for r in csv_rows)
    best_mAP50_95 = max(float(r["metrics/mAP50-95(B)"]) for r in csv_rows)
    best_mAP50_epoch = -1
    for i, r in enumerate(csv_rows):
        if float(r["metrics/mAP50(B)"]) == best_mAP50:
            best_mAP50_epoch = i + 1
            break
    final_train_box_loss = float(last_row["train/box_loss"])
    final_train_cls_loss = float(last_row["train/cls_loss"])
    final_train_dfl_loss = float(last_row["train/dfl_loss"])
    final_val_box_loss = float(last_row["val/box_loss"])
    final_val_cls_loss = float(last_row["val/cls_loss"])
    final_val_dfl_loss = float(last_row["val/dfl_loss"])
    total_time_h = float(last_row["time"]) / 3600.0
    print(f"      {total_epochs} epochs loaded, best mAP50={best_mAP50:.4f} @ epoch {best_mAP50_epoch}")
    print()

    print("[3/3] Generating report...")

    box = val_results.box
    ap_class_index = []
    if hasattr(box, "ap_class_index") and box.ap_class_index is not None:
        ap_class_index = box.ap_class_index.tolist()

    per_class_mAP50 = [None] * len(CLASS_NAMES)
    per_class_mAP50_95 = [None] * len(CLASS_NAMES)

    if hasattr(box, "ap50") and box.ap50 is not None:
        ap50_vals = box.ap50.tolist()
        for idx, cls_id in enumerate(ap_class_index):
            if idx < len(ap50_vals) and 0 <= cls_id < len(CLASS_NAMES):
                per_class_mAP50[cls_id] = round(ap50_vals[idx], 4)

    if hasattr(box, "maps") and box.maps is not None:
        maps_vals = box.maps.tolist()
        if maps_vals and isinstance(maps_vals, list):
            if len(maps_vals) == len(ap_class_index) + 1:
                for idx, cls_id in enumerate(ap_class_index):
                    if 0 <= cls_id < len(CLASS_NAMES):
                        per_class_mAP50_95[cls_id] = round(maps_vals[1 + idx], 4)
            elif len(maps_vals) == len(ap_class_index):
                for idx, cls_id in enumerate(ap_class_index):
                    if 0 <= cls_id < len(CLASS_NAMES):
                        per_class_mAP50_95[cls_id] = round(maps_vals[idx], 4)

    per_class_records = []
    for i, name in enumerate(CLASS_NAMES):
        per_class_records.append({
            "name": name,
            "mAP50": per_class_mAP50[i] if per_class_mAP50[i] is not None else "N/A",
            "mAP50_95": per_class_mAP50_95[i] if per_class_mAP50_95[i] is not None else "N/A",
        })

    if hasattr(box, "mp") and box.mp is not None:
        precision = float(box.mp)
    elif box.p is not None:
        precision = float(box.p[0]) if len(box.p) > 0 else 0
    else:
        precision = 0

    if hasattr(box, "mr") and box.mr is not None:
        recall = float(box.mr)
    elif box.r is not None:
        recall = float(box.r[0]) if len(box.r) > 0 else 0
    else:
        recall = 0

    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    lines = []
    lines.append("# PCB 缺陷检测模型 — 训练验证报告")
    lines.append("")
    lines.append(f"> 生成时间：{now_str}")
    lines.append(f"> 模型文件：`pcb_defect_det.pt`（YOLOv8n）")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 1. 训练配置")
    lines.append("")
    lines.append("| 项目 | 配置 |")
    lines.append("|------|------|")
    lines.append("| 基础模型 | yolov8n.pt |")
    lines.append("| 任务类型 | 6 类缺陷检测 |")
    lines.append("| 训练轮数 | 100 epochs |")
    lines.append("| 批次大小 | 8 |")
    lines.append("| 输入尺寸 | 640 × 640 |")
    lines.append("| 优化器 | SGD（自动） |")
    lines.append("| 初始学习率 | 0.01 |")
    lines.append("| 学习率策略 | Cosine（最终系数 0.01） |")
    lines.append("| 动量 | 0.937 |")
    lines.append("| 权重衰减 | 0.0005 |")
    lines.append("| 预热轮数 | 3 epochs |")
    lines.append("| 数据增强 | Mosaic、HSV、平移、缩放、水平翻转、随机擦除 |")
    lines.append("| 早停耐心 | 30 epochs |")
    lines.append("| 训练设备 | CUDA（NVIDIA RTX 3060 Laptop） |")
    lines.append("")
    lines.append("**缺陷类别**")
    lines.append("")
    lines.append("| 编号 | 类别名称 | 说明 |")
    lines.append("|------|----------|------|")
    lines.append("| 0 | Mouse_bite | 鼠咬 |")
    lines.append("| 1 | Spur | 毛刺 |")
    lines.append("| 2 | Missing_hole | 漏孔 |")
    lines.append("| 3 | Short | 短路 |")
    lines.append("| 4 | Open_circuit | 断路 |")
    lines.append("| 5 | Spurious_copper | 残铜 |")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 2. 验证集测试结果")
    lines.append("")
    lines.append("验证集共 100 张图片、426 个缺陷标注实例。")
    lines.append("")
    lines.append("### 2.1 整体指标")
    lines.append("")
    lines.append("| 指标 | 数值 |")
    lines.append("|------|------|")
    lines.append(f"| **mAP@0.5** | **{val_results.box.map50:.4f}** |")
    lines.append(f"| **mAP@0.5:0.95** | **{val_results.box.map:.4f}** |")
    lines.append(f"| 精确率（宏平均） | {precision:.4f} |")
    lines.append(f"| 召回率（宏平均） | {recall:.4f} |")
    lines.append("")
    lines.append("### 2.2 逐类检测精度")
    lines.append("")
    lines.append("| 缺陷类别 | mAP@0.5 | mAP@0.5:0.95 | 评价 |")
    lines.append("|----------|---------|---------------|------|")

    for r in per_class_records:
        map50_val = r['mAP50']
        map5095_val = r['mAP50_95']
        map50_str = f"{map50_val:.4f}" if isinstance(map50_val, float) else str(map50_val)
        map5095_str = f"{map5095_val:.4f}" if isinstance(map5095_val, float) else str(map5095_val)

        if isinstance(map50_val, float):
            if map50_val >= 0.98:
                grade = "★ 极优"
            elif map50_val >= 0.93:
                grade = "☆ 优秀"
            elif map50_val >= 0.88:
                grade = "良好"
            else:
                grade = "一般"
        else:
            grade = "—（验证集无实例）"

        lines.append(f"| {r['name']} | {map50_str} | {map5095_str} | {grade} |")
    lines.append("")
    lines.append("### 2.3 推理速度")
    lines.append("")
    sp = val_results.speed
    if sp:
        lines.append("| 阶段 | 耗时（ms/张） |")
        lines.append("|------|---------------|")
        lines.append(f"| 预处理 | {sp.get('preprocess', 0):.1f} |")
        lines.append(f"| 推理 | {sp.get('inference', 0):.1f} |")
        lines.append(f"| 损失计算 | {sp.get('loss', 0):.1f} |")
        lines.append(f"| 后处理 | {sp.get('postprocess', 0):.1f} |")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 3. 训练过程概要")
    lines.append("")
    lines.append("| 项目 | 数值 |")
    lines.append("|------|------|")
    lines.append(f"| 总轮数 | {total_epochs} |")
    lines.append(f"| 最佳 mAP@0.5 | {best_mAP50:.4f}（第 {best_mAP50_epoch} 轮） |")
    lines.append(f"| 最佳 mAP@0.5:0.95 | {best_mAP50_95:.4f} |")
    lines.append(f"| 训练总耗时 | {total_time_h:.2f} 小时 |")
    lines.append("")
    lines.append("### 3.1 最终轮损失值")
    lines.append("")
    lines.append("| 损失项 | 训练集 | 验证集 |")
    lines.append("|--------|--------|--------|")
    lines.append(f"| Box 损失 | {final_train_box_loss:.4f} | {final_val_box_loss:.4f} |")
    lines.append(f"| 分类损失 | {final_train_cls_loss:.4f} | {final_val_cls_loss:.4f} |")
    lines.append(f"| DFL 损失 | {final_train_dfl_loss:.4f} | {final_val_dfl_loss:.4f} |")
    lines.append("")
    lines.append("### 3.2 mAP 变化趋势（每 10 轮）")
    lines.append("")
    lines.append("| 轮次 | mAP@0.5 | mAP@0.5:0.95 | 精确率 | 召回率 |")
    lines.append("|------|---------|---------------|--------|--------|")
    for i in [0, 9, 19, 29, 39, 49, 59, 69, 79, 89, 99]:
        if i < len(csv_rows):
            r = csv_rows[i]
            lines.append(
                f"| {i+1} | {float(r['metrics/mAP50(B)']):.4f} | "
                f"{float(r['metrics/mAP50-95(B)']):.4f} | "
                f"{float(r['metrics/precision(B)']):.4f} | "
                f"{float(r['metrics/recall(B)']):.4f} |"
            )
    lines.append("")
    lines.append("mAP@0.5 在前 20 轮迅速上升至 0.80，随后稳定增长，至第 85 轮达到峰值 0.9313，训练后期略有波动但整体收敛良好。")
    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append("## 4. 模型信息")
    lines.append("")
    lines.append("| 项目 | 数值 |")
    lines.append("|------|------|")
    lines.append("| 参数量 | 3,006,818 |")
    lines.append("| 计算量 (FLOPs) | 8.1 G |")
    lines.append("| 网络层数 | 73（融合后） |")
    lines.append("")

    os.makedirs(REPORT_DIR, exist_ok=True)
    with open(REPORT_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    print(f"      Report saved to: {REPORT_PATH}")
    print()
    print("=" * 60)
    print("Done!")
    print("=" * 60)


if __name__ == "__main__":
    generate_report()
