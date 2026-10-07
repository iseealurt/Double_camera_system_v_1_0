# DC-CVS 双目立体视觉系统（FPGA + 上位机）

基于国产 FPGA 的双目立体视觉系统（Double-Camera Computer Vision System）：

- **FPGA 端**：两颗 OV5640 同步采集 640x480 双目图像 → DDR3 帧缓存与 AXI 仲裁 → 硬件 Census 变换 + SGM（半全局匹配）视差计算 → HDMI 1080P 视差图叠加显示
- **上位机端**：Python/PyQt 图形界面，完成双目画面接入、视差热力图与点云显示、测距、PCB 目标/缺陷检测（YOLOv8）与 PnP 位姿估计

---

## 一、目录结构

| 目录 / 文件 | 说明 |
|---|---|
| `RTL_code/` | FPGA 工程 RTL 源码（顶层、采集层、缓存/仲裁层、SGM 算法、显示层、UART 等） |
| `ipcore/` | 紫光同创 IP 生成器生成的 IP 核源码（FIFO / RAM / PLL / DDR3 控制器等） |
| `constrain/` | 时序约束（.fdc）与管脚约束（.pcf） |
| `Prj/` | Pango 工程文件 `OV_DDR_HDMI_v_2_0.pds`，使用 `../` 相对路径引用上述源码与约束 |
| `Verification_model/` | 系统级验证模型（DDR 行为模型、顶层仿真 wrapper、文件列表脚本） |
| `Behave_simulation/` | ModelSim/Questa 行为仿真脚本（编译/仿真 tcl、波形脚本） |
| `Bench/` | 模块级/子系统级 testbench 与测试向量（.dat）、比对图片 |
| `history/` | SGM 算法历史版本存档 |
| `Matlab/` | Matlab/Python 验证脚本、双目标定参数与 LUT、验证报告图 |
| `Software/` | 上位机软件（`Source_Code/` 源码、`weights/` 训练权重、开发计划与训练报告） |
| `docs/` | 项目技术总结、代码实现总结、算法架构图（Visio）、上位机设计文档 |
| `runs/` | 上位机目标检测验证结果示例图 |

## 二、硬件平台与工具链

| 项目 | 说明 |
|---|---|
| FPGA | 紫光同创 PGL50H-6-FBG484（MES50HP 开发板） |
| 开发工具 | Pango Design Suite (Fabric Compiler) 2022.2-SP6.4 |
| 仿真工具 | ModelSim / Questa（脚本默认 `bin_path=C:/modeltech64_2020.4/win64`，请按本机安装路径修改） |
| 摄像头 | OV5640 × 2（DVP 接口，640x480） |
| 存储 | 外挂 DDR3 SDRAM（帧缓存 + 视差缓存） |
| 显示 | HDMI 1080P |
| 上位机 | Python 3.x + PyQt5 + OpenCV + ultralytics（见 `Software/Source_Code/requirements.txt`） |

## 三、快速开始

### 1. FPGA 工程（Pango PDS）

1. 保持仓库目录结构不变，用 Pango Design Suite 打开 `Prj/OV_DDR_HDMI_v_2_0.pds`；
2. 工程内源码/约束/IP 均以 `../RTL_code`、`../ipcore`、`../constrain` 相对路径引用，请勿改动顶层目录名；
3. 依次执行 综合 → 布局布线 → 生成位流。

> 说明：RTL 中的 `` `include `` 宏（如 `Disp_param.vh`、`ddr3_parameters.vh`）使用相对路径 `../`，请将工具的工作目录设置为工程根目录下的一级子目录（如 `Prj/` 或 `Behave_simulation/`），或按需在工具中添加 include 搜索路径。

### 2. 行为仿真（ModelSim / Questa）

1. 进入 `Behave_simulation/`，按本机 ModelSim 安装路径修改 `run_behav.bat` 中的 `bin_path`；
2. 运行 `run_behav.bat`（内部依次执行 `run_behav_compile.tcl`、`run_behav_simulate.tcl`）；
3. 其余仿真场景脚本位于 `Behave_simulation/frame_switch_sim/` 与 `Behave_simulation/sim_log/sgm/`。
   其中 `sim_log/sgm/run_behav_compile.tcl` 中 PDS 仿真库路径以 `PDS_SIM_LIB_PATH/` 占位，请按本机 Pango 安装目录修改。

### 3. Matlab 验证脚本

- 脚本位于 `Matlab/script/`，请在 Matlab 中将工作目录切换到该目录后运行（脚本内数据路径为相对路径）；
- 标定相关数据位于 `Matlab/calibration/`（如需完整 LUT，可用 `stereo_calibration.m` 重新生成）；
- 验证报告图位于 `Matlab/verification/`。

### 4. 上位机软件

1. 安装依赖：`pip install -r Software/Source_Code/requirements.txt`；
2. 运行：`python Software/Source_Code/main.py`；
3. 训练好的检测权重位于 `Software/Source_Code/weights/`（PCB 目标检测 / 缺陷检测），可直接使用；
4. 训练配置参考 `weights/pcb_defect_det/data.yaml` 与 `Software/AI/report.md`（训练验证报告）。

## 四、数据与第三方内容说明

- 出于体积与版权考虑，以下内容**未包含**在本仓库中，如需复现请自行准备：
  - PCB 缺陷检测训练数据集（图片数据）；
  - 立体匹配测试图集（Middlebury 等第三方样本集，仅保留少量测试向量）；
  - 第三方算法参考代码；
- `ipcore/` 中 DDR3 控制器等 IP 由 Pango Design Suite 官方 IP 生成器生成，请遵守工具随附的许可条款；
- 校验/比对用的少量测试向量（`Bench/*.dat`、`Matlab/test img/census_dat` 等）已保留，可直接复现仿真与验证流程。

## 五、许可证

本仓库暂未附加开源许可证（LICENSE），发布前请根据您的意愿补充（如 MIT / Apache-2.0 / GPL 等）；第三方 IP 与工具生成代码请遵循其原始许可。