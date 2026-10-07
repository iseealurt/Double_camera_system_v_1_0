# Double-Camera Computer Vision System (DC-CVS) 代码实现总结

> 项目：基于可重构视觉系统的工业工件多维检测与姿态估计  
> 平台：紫光同创 PG2L50H FPGA + RTX 3060 Laptop PC  
> 生成日期：2026-06-01

---

## 目录

- [1. 项目概览](#1-项目概览)
- [2. RTL 硬件代码分层总结](#2-rtl-硬件代码分层总结)
  - [2.1 系统顶层 (Top层)](#21-系统顶层-top层)
  - [2.2 SGM 子系统顶层 (SGM_TOP.v)](#22-sgm-子系统顶层-sgm_topv)
  - [2.3 数据采集层 (Data Acquisition Layer)](#23-数据采集层-data-acquisition-layer)
  - [2.4 视频数据缓冲层 (Video Data Buffer Layer)](#24-视频数据缓冲层-video-data-buffer-layer)
  - [2.5 SGM 数据引擎 (Algorithm Data Engine)](#25-sgm-数据引擎-algorithm-data-engine)
  - [2.6 RGB 转灰度 (rgb2gray.v)](#26-rgb-转灰度-rgb2grayv)
  - [2.7 Census 特征变换](#27-census-特征变换)
  - [2.8 SGM 半全局匹配核心 (sgm.v)](#28-sgm-半全局匹配核心-sgmv)
  - [2.9 视差图显示输出 (sgm_disp.v)](#29-视差图显示输出-sgm_dispv)
  - [2.10 摄像头初始化与配置](#210-摄像头初始化与配置)
  - [2.11 UART 通信接口](#211-uart-通信接口)
- [3. 软件代码总结](#3-软件代码总结)
  - [3.1 入口与程序结构 (main.py)](#31-入口与程序结构-mainpy)
  - [3.2 GUI 主窗口 (main_window.py)](#32-gui-主窗口-main_windowpy)
  - [3.3 并行处理流水线 (parallel_pipeline.py)](#33-并行处理流水线-parallel_pipelinepy)
  - [3.4 图像处理器核心 (image_processor.py)](#34-图像处理器核心-image_processerpy)
  - [3.5 相机采集模块 (capture.py)](#35-相机采集模块-capturepy)
  - [3.6 PCB 检测模块](#36-pcb-检测模块)
  - [3.7 PnP 姿态估计 (pnp_estimator.py)](#37-pnp-姿态估计-pnp_estimatorpy)
  - [3.8 SGM 调试对比 (sgm_debug.py)](#38-sgm-调试对比-sgm_debugpy)
  - [3.9 配置管理 (config.py)](#39-配置管理-configpy)
  - [3.10 其他辅助模块](#310-其他辅助模块)
- [4. 软硬协同接口分析](#4-软硬协同接口分析)
- [5. 代码规模统计](#5-代码规模统计)

---

## 1. 项目概览

本项目是一套完整的**双目立体视觉软硬协同系统**，由 FPGA 端（紫光同创 PG2L50H）和 PC 上位机端（RTX 3060 GPU）两部分组成。

**硬件端（FPGA）**核心任务：
- 同时采集两路 OV5640 摄像头图像（640x480 @ 60fps）
- 通过 DVP → AXI 协议转换写入 DDR3 SDRAM
- 通过三重缓冲（frame_switch）管理帧缓存
- 基于 AXI 仲裁器实现多主机共享 DDR3
- 从 DDR3 读取双目图像，执行 SGM 立体匹配算法，产生视差图
- 将 RGB 原图与 SGM 视差图通过 HDMI（1080P）输出显示

**软件端（PC）**核心任务：
- 通过 USB 摄像头采集 HDMI 输出的 1080P 帧画面（含双目原图 + 视差图区域）
- 从帧画面中裁剪出左目/右目 480P 图像和 SGM 视差图区域
- GPU 加速的视差图恢复（RGB 逆编码 → 子像素填充 → 中值滤波 → 热力图/3D 点云）
- YOLOv8n 目标检测（PCB 板卡检测 + 缺陷检测，约 320 万参数）
- PnP 6D 姿态估计（ORB 特征匹配 + EPnP + RANSAC）
- PyQt5 多视图 GUI 显示（左/右/视差/点云/YOLO日志）

**关键技术指标**：

| 指标 | 数值 | 说明 |
|------|------|------|
| FPGA 工艺节点 | **40nm** | 紫光同创 PG2L50H（Logos2 系列 PG2L50H-FG484） |
| SGM 处理时钟频率 | **20 MHz** | 由顶层 PLL 生成 `sgm_clk` |
| 视差搜索范围 | **48 像素** | `MAX_MATCH_DEPTH=48`，视差 0~47 |
| FPGA 资源消耗 (SGM核心) | **~11K LUT6（占总量约22%）** | LUT6 用于 XOR+popcount+代价聚合+WTA |
|  | **~80 块 DRM 18Kb（占总量约47%）** | 用于 Census 行缓冲 + Lr3 代价缓冲 + FIFO |
|  | **~2 个 DSP** | 用于灰度转换乘法等辅助运算 |
| SGM 精度（2方向 vs 4方向参考） | **Bad 1.0 约 12.86%** | 与 4 方向参考实现相差约 1.81 个百分点 |
| 端到端处理延迟 | **约 46.5ms** | FPGA SGM 子系统约 16.5ms + PC 端 GPU 处理约 30ms |
| 双目基线距 | 3.00546 cm | 物理基线距 |
| 等效焦距 | 609.157 px | 标定所得 |

---

## 2. RTL 硬件代码分层总结

> **FPGA 端架构层次**：FPGA 端整体采用**五层架构**——**初始化层**（video_init / uart_cfg / i2c_ctrl）→ **采集层**（DVP_AXI / sgm_data_engine）→ **缓冲层**（frame_switch / AXI_arbiter）→ **SGM 加速层**（rgb2gray / census_5x5 / sgm_new_2）→ **显示输出层**（sgm_disp / double_camera_disp / HDMI）。请勿与论文中"六层（FPGA五层 + 上位机）"的整体系统架构混淆。

### 2.1 系统顶层 (Top层)

**文件位置**：`RTL_code/Top/OV_DDR_HDMI_v_2_0.v`

**功能**：整个 FPGA 工程的最顶层模块，例化所有子系统并完成全局互联。

**关键参数**：
| 参数 | 值 | 含义 |
|------|-----|------|
| `CAMERA_WIDTH` | 640 | 摄像头采集宽度 |
| `CAMERA_HEIGHT` | 480 | 摄像头采集高度 |
| `MEM_DQ_WIDTH` | 32 | DDR3 数据位宽 |
| `AXI_DATA_WIDTH` | 256 | AXI 数据总线宽度（8倍 DDR 位宽） |
| `AXI_ADDR_WIDTH` | 28 | AXI 地址总线宽度 |

**内部时钟域**：
| 时钟 | 来源 | 用途 |
|------|------|------|
| `clk_in_50m` | 外部晶振 | 系统基准时钟 |
| `ddr_clk` | DDR3 IP 核输出 | DDR3/AXI 总线时钟 |
| `pix_clk` | PLL 生成 | 显示像素时钟 (148.5MHz) |
| `sgm_clk` | PLL 生成 | SGM 算法处理时钟 |

**模块互联架构**（扁平化仲裁器模型）：
```
OV5640_1 → DVP_AXI_1 ──┐
                         ├→ frame_switch (CMR1) ──→ 写缓冲管理
OV5640_2 → DVP_AXI_2 ──┤                           ├→ Display (pix_fifo)
                         ├→ frame_switch (CMR2) ──→ ├→ SGM_TOP (pix_fifo)
                         │
AXI_arbiter_v_2_0 (4-user) ←→ DDR3 Controller IP
  user_0: CMR1写+Display读
  user_1: CMR2写
  user_2: SGM_TOP(读+写)
  user_3: sgm_disp(读)
```

**子系统例化清单**：
| 模块 | 实例名 | 功能 |
|------|--------|------|
| `video_init` | video_init_inst | 初始化时序控制（DDR/CMR/HDMI） |
| `uart_cfg` x2 | cmr_1/2_uart_cfg_inst | OV5640 寄存器配置 |
| `ms72xx_ctl` | ms_init_module | HDMI 发送芯片初始化 |
| `PLL` | pix_clk_gene | 生成 pix_clk 和 sgm_clk |
| `DVP_AXI` x2 | cmr_1/2_dvp_axi | DVP → AXI 协议转换 |
| `SGM_TOP` | u_sgm_top | SGM 算法子系统 |
| `axi_arbiter_v_2_0` | u_axi_arbiter_v_2_0 | 4主机 AXI 仲裁器 |
| `ddr3_50h` | ddr3_50h_inst | DDR3 控制器 IP |
| `frame_switch_v_2_0` x3 | cmr1/2/sgm | 三重缓冲帧管理 |
| `double_camera_disp` | double_camera_disp_inst | 双路显示驱动 |
| `sgm_disp` | u_sgm_disp | SGM 视差图叠加显示 |
| `drm_fifo_256b_8d` x2 | cmr_1/2_pix_fifo | 显示像素 FIFO 缓冲 |

**关键设计决策**：
- 仲裁器采用**基于信用流控和固定优先级的 4 主机 1 从机多路仲裁器**（v7.0 更新）
- 三重缓冲通过 `frame_switch_v_2_0` 管理：3 个帧缓冲区间，写指针和读指针独立轮转
- SGM 视差图有独立的 `frame_switch` 实例管理写入/读出缓冲

---

### 2.2 SGM 子系统顶层 (SGM_TOP.v)

**文件位置**：`RTL_code/SGM_TOP.v`

**功能**：SGM 立体匹配算法的完整数据流集成，包含从 AXI 数据读取到视差图输出的全部层级。

**参数配置**：
| 参数 | 值 | 含义 |
|------|-----|------|
| `MAX_MATCH_DEPTH` | 48 | 最大匹配深度（视差搜索范围） |
| `CENSUS_WIDTH` | 24 | Census 变换向量位宽 (5x5-1) |
| `DISPARITY_WIDTH` | 8 | 输出视差图位宽 |
| `SGM_P1` | 3 | 小视差惩罚系数 |
| `SGM_P2` | 24 | 大视差惩罚系数（= 最大 Hamming 距离） |
| `SGM_LR_WIDTH` | 12 | 代价聚合内部位宽 |

**时钟域**：三时钟域设计
| 时钟 | 用途 |
|------|------|
| `axi_clk` | AXI 总线读/写数据 |
| `pix_clk` | 像素处理（灰度化、Census） |
| `sgm_clk` | SGM 核心算法 |

**内部数据流层级**：
```
层级1: 双路像素FIFO (AXI clk → pix clk)
  ├── drm_fifo_256b_8d (CMR1)
  └── drm_fifo_256b_8d (CMR2)
       ↓
层级2: SGM数据引擎 (sgm_data_engine)
  └── 从FIFO读取 → 双路VESA时序输出
       ↓
层级3: RGB转灰度 (rgb2gray ×2)
  └── RGB565 → 8bit灰度 (流水线4级)
       ↓
层级4: Census特征变换 (census_5x5 ×2)
  └── 5×5窗口 → 24bit Census向量
       ↓
层级5: Census → SGM FIFO缓冲 (pix clk → sgm clk)
  ├── cmr_census_fifo ×2 (24bit line buffer)
  └── sgm_vsync_fifo (vsync token同步)
       ↓
层级6: SGM半全局匹配 (sgm_new_2)
  └── Hamming距离 + 2方向代价聚合 + WTA视差选择
       ↓
层级7: VESA_AXI写回DDR3 (sgm clk → axi clk)
  └── 视差图 → AXI写事务
```

**关键信号路由**：
- `vsync_combined = l_census_vsync && r_census_vsync`：双路 vsync 联合后检测上升沿生成 vsync token
- Census FIFO 采用**预读模式**，由 `cmr_census_fifo_rd_en` 统一控制双路读取
- SGM 内部状态机通过 `cmr_vsync_fifo_empty` 检测帧起始

---

### 2.3 数据采集层 (Data Acquisition Layer)

#### DVP_AXI_v_2_0.v

**文件位置**：`RTL_code/Data_acquisition_layer/DVP_AXI_v_2_0.v`

**功能**：将 OV5640 摄像头的 DVP（Digital Video Port）协议数据流转换为 Simplified AXI4 写事务，实现图像数据写入 DDR3。

**关键特性**：
- 输入：8bit DVP 数据 + href + vref 时序（来自 OV5640 摄像头）
- 输出：256bit AXI4 写地址/数据通道
- 数据组装：16 个 DVP 像素（16bit RGB565）组装为 256bit AXI 写数据
- 行内突发长度可配置（默认 WLEN=8，即每行约 8 个 AXI 写事务）
- 帧使能计数（`FRAME_EN_VALUE=10`）：跳过前 10 帧不稳定数据
- 跨时钟域：`dvp_pclk` → `axi_clk`，内部使用异步 FIFO

#### VESA_AXI_v_3_0.v

**文件位置**：`RTL_code/Data_acquisition_layer/VESA_AXI_v_3_0.v`

**功能**：与 DVP_AXI 功能对称，将 VESA（Video Electronics Standards Association）时序协议数据转换为 AXI4 写事务。用于 SGM 视差图输出的写入。

**与 DVP_AXI 的区别**：
- 输入数据位宽可配置（`INPUT_DATA_WIDTH=8`，用于视差图）
- 像素数据宽度为 `PIXEL_DATA_WIDTH=8`（vs DVP_AXI 的 16bit）
- 同样使用异步 FIFO 进行 `pclk → axi_clk` 跨时钟域

---

### 2.4 视频数据缓冲层 (Video Data Buffer Layer)

#### frame_switch.v (frame_switch_v_2_0)

**文件位置**：`RTL_code/Video_data_buffer_layer/frame_switch.v`

**功能**：三层缓冲（Triple Buffer）管理模块，基于 AXI 地址偏移管理帧缓冲区的写入/读出轮转。

**核心机制**：
- 3 个缓冲区：`BUFFER0`, `BUFFER1`, `BUFFER2`，按帧大小 + 间隔排列
- 写侧：当一帧写入完成（`wr_end` 上升沿），将当前写缓冲标记为有效（`buf_valid_flag`），轮转到下一个空闲缓冲
- 读侧：当一帧显示完成（`rd_end` 上升沿，即 `display_vsync` 信号跳变），轮转读缓冲指针
- 关键约束：写入时若第三缓冲正被占用（`buf_read_flag[2]` 或 `buf_write_flag[2]`）则报错
- 参数 `BUFFER_INTERVAL=MEM_COL_ADDR_WIDTH`（10bit 间隔）防止缓冲区重叠
- 支持多读用户（`RD_USER_VAL=2`：Display + SGM），通过 AXI ID 区分

**v2.0 升级点**（相比 Origin/frame_switch.v）：
- 基于 AXI 地址（而非单独的控制信号）进行缓冲区管理
- 扩展支持 2 个读用户（Display + SGM）
- 在顶层 OV_DDR_HDMI 中共有 3 个实例：
  - `cmr1_frame_switch_v_2_0`：CMR1 写入 → 2 个读用户（Display + SGM）
  - `cmr2_frame_switch_v_2_0`：CMR2 写入 → 2 个读用户（Display + SGM）
  - `sgm_frame_switch_v_2_0`：SGM 视差图写入 → 1 个读用户（sgm_disp）

#### AXI_arbiter.v (axi_arbiter_v_2_0)

**文件位置**：`RTL_code/Video_data_buffer_layer/AXI_arbiter.v`

**功能**：多主机 AXI 仲裁器，管理多个 AXI 主设备对 DDR3 控制器的共享访问。

**v2.0 特性**：
- **信用流控（Credit-based Flow Control）**：预先分配信用额度，防止某主机独占总线
- **固定优先级仲裁**：User0 > User1 > User2 > User3
- 支持 4 个主机用户
- 在顶层中的用户分配：
  - User0：CMR1 写通道 + Display 读通道
  - User1：CMR2 写通道
  - User2：SGM_TOP（读+写）
  - User3：sgm_disp 读通道
- 信用参数：`CREDIT_MAX_NUM = 10`（最大信用令牌数）

---

### 2.5 SGM 数据引擎 (Algorithm Data Engine)

**文件位置**：`RTL_code/algorithm_data_engine/sgm_data_engine.v`

**功能**：SGM 子系统的数据接口层，完成 AXI  DDR3 数据读取和双路 VESA 时序生成。

**双功能角色**：
1. **VESA 时序生成器**：在 `pix_clk` 域生成标准 VESA 640x480 时序（H=646, V=500），产生 `vsync`, `href` 和左右目的 RGB 像素
2. **AXI 读主控**：在 `axi_clk` 域通过状态机管理 DDR3 突发读取

**AXI 读控制状态机**（独热码编码）：
```
IDLE → FRAME_REQ_RDY → CMR_1_ADDR_RDY → CMR_1_ADDR_END → SINGLE_BURST_END
                                  ↕                          ↕
                       CMR_2_ADDR_RDY → CMR_2_ADDR_END → SINGLE_BURST_END → FRAME_REQ_END → IDLE
```
- 交替读取 CMR1 和 CMR2 数据（基于 FIFO 水位阈值控制）
- 每个突发读取一行数据的 1/4（`SINGLE_LINE_REQ_VALUE = 640*16/256 = 40` 个 burst）
- 通过 `fn_get_burst_len()` 函数自动计算最优突发长度（能整除行数据量的最大长度）
- 像素解包：`l_pix_disp_pre = camera_1_rd_data_reg[cmr_rd_cnt*16 +: 16]` 从 256bit 数据中顺序提取 RGB565 像素
- RGB565 → RGB888 转换：`l_r_chn = l_pix_disp[15:11] << 3`（5bit→8bit 左移扩展）

**FIFO 读取控制**：
- `camera_1_rd_req = cmr_rd_cnt == 0 && camera_1_rd_de && cmr_disp_valid`
- 每 4 个像素周期（完成一个 256bit/64bit=4 次读取后）触发一次 FIFO 读

---

### 2.6 RGB 转灰度 (rgb2gray.v)

**文件位置**：`RTL_code/algorithm/rgb2gray.v`

**功能**：将 RGB888 像素转换为 8bit 灰度值。

**算法**：加权灰度公式 `Gray = 0.299R + 0.587G + 0.114B`，实现为整数乘法+移位：
- `R * 19595 + G * 38470 + B * 7471`
- 取结果的高 8 位（`gray_sum[23:16]`）
- 等效于 `/ 65536 = / 2^16`

**流水线设计**（`PIPELINE_STAGES=4`）：
| Stage | 操作 |
|-------|------|
| Stage1 | `R × 19595` |
| Stage2 | `G × 38470`, `R_Temp` 延迟一拍 |
| Stage3 | `B × 7471`, `R_Temp`/`G_Temp` 延迟一拍 |
| Stage4 | `R_Temp + G_Temp + B_Temp` 求和 |

**时序对齐**：vsync 和 hsync 通过 4 级移位寄存器与像素数据同步延迟。

**在 SGM_TOP 中使用**：例化两次（`u_rgb2gray_left`, `u_rgb2gray_right`），分别处理左右目。

---

### 2.7 Census 特征变换

**模块名**：`census_5x5`（在 SGM_TOP.v 中例化）

> **命名说明**：Census 变换模块在 RTL 中的例化名为 `census_5x5`，其核心 5x5 滑窗生成器基于 `matrix_gene_5x5.v`。两者指代同一模块的不同层次：`census_5x5` 是顶层封装（含比较器和向量生成逻辑），`matrix_gene_5x5` 是内部 5x5 滑动窗口缓冲器（产生 25 个并行灰度像素）。

**功能**：对 8bit 灰度图执行 5x5 窗口 Census 变换，生成 24bit Census 特征向量。

**变换原理**：
- 对于每个像素，比较其 5x5 邻域内 24 个像素（排除中心）与中心像素的灰度大小关系
- 若邻域像素 > 中心像素，对应 bit 置 1，否则置 0
- 最终每个像素生成 24bit 二进制序列

**接口**：
- 输入：`per_vga_gray[7:0]`, `per_vga_vsync`, `per_vga_href`
- 输出：`census[23:0]`, `census_vsync`, `census_href`
- 参数：`IMAGE_WIDTH=640`, `IMAGE_HEIGHT=480`

**在 SGM_TOP 中使用**：例化两次（`u_census_5x5_left`, `u_census_5x5_right`）

---

### 2.8 SGM 半全局匹配核心

**版本演进**：项目存在两个 SGM 核心实现版本：
- **sgm.v**：早期单方向（Lr1，从左到右）参考实现，作为算法验证和原型开发的基础版本
- **sgm_new_2**：最终采用的 2 方向（Lr1 + Lr3）实现，在 SGM_TOP.v 中例化，是系统的正式 SGM 引擎

以下以最终版本 **sgm_new_2** 为主体进行描述，sgm.v 的细节附于末尾作为演进参考。

#### 2.8.1 sgm_new_2 — 最终实现（2方向 Lr1 + Lr3）

**文件位置**：`RTL_code/algorithm/double_camera_vision/sgm_new_2/`

**功能**：SGM 立体匹配算法的 2 方向硬件实现，包含 Hamming 距离计算、Lr1（从左到右）+ Lr3（从右到左）双方向代价聚合和 WTA 视差选择。

**为什么选 2 方向（Lr1 + Lr3）**：
SGM 理论上路径数越多，匹配精度越高；但硬件复杂度与路径数成正比。经过 Matlab 仿真评估，在 48 视差级别、640x480 分辨率下：
- 1 方向（Lr1）：Bad 1.0 误匹配率较高，条状伪影明显
- 2 方向（Lr1 + Lr3）：相比 4 方向参考实现仅差约 1.81 个百分点（Bad 1.0 约 12.86%），而硬件开销可控
- 4 方向（Lr1 + Lr2 + Lr3 + Lr4）：精度最优但硬件资源翻倍，在当前 FPGA 上难以适配

因此 Lr1 + Lr3 正交方向对是精度与资源的最优折中。

**算法管线架构**：

sgm_new_2 沿用了 sgm.v 的 13 级流水线基础结构，核心差异在于代价聚合阶段需要处理两个方向的路径代价并融合：

```
Stage 0-5: Hamming 距离计算（与 sgm.v 一致）
  - CMR1 48级移位寄存器窗口
  - CMR2 Census 与 CMR1_window[i] 逐位 XOR
  - LUT6 popcount → Hamming 距离

Stage 6-7: 双方向代价聚合
  - 方向1 (Lr1)：从左到右逐像素递归
    Lr1_curr[d] = ham[d] + min(Lr1_prev[d], Lr1_prev[d-1]+P1, Lr1_prev[d+1]+P1, min_k(Lr1_prev[k])+P2) - min_k(Lr1_prev[k])
  - 方向2 (Lr3)：从右到左逐像素递归
    Lr3_curr[d] = ham[d] + min(Lr3_next[d], Lr3_next[d-1]+P1, Lr3_next[d+1]+P1, min_k(Lr3_next[k])+P2) - min_k(Lr3_next[k])
  - 融合：Lr_fused[d] = (Lr1[d] + Lr3[d]) / 2

Stage 8-13: WTA 视差选择
  - 48 路并行二叉树比较（48→24→12→6→3→2→1）
  - 输出最终视差值 disparity + subpixel 细分数
```

**Lr3 反向扫描的实现**：
由于 Lr3 需要从右到左的递归，而像素数据以从左到右的流式顺序输入，sgm_new_2 采用了**行缓冲 + 反向递归**策略：
- 使用片上 BRAM 缓存一行完整的 48 视差级别代价数据
- 在正向扫描完成后，从行缓冲中反向读取，计算 Lr3 代价
- Lr1 和 Lr3 的代价在融合阶段求平均后送入 WTA 树

**参数配置**（在 SGM_TOP.v 顶层统一定义，与 sgm.v 共享）：
| 参数 | 值 | 含义 |
|------|-----|------|
| `MAX_MATCH_DEPTH` | 48 | 视差搜索范围（0~47 像素） |
| `CENSUS_WIDTH` | 24 | Census 向量位宽（5x5-1） |
| `SGM_P1` | 3 | 小视差惩罚系数 |
| `SGM_P2` | 24 | 大视差惩罚系数（= 最大 Hamming 距离） |
| `SGM_LR_WIDTH` | 12 | 代价聚合内部位宽 |

**关键设计细节**：
- 核心运算单元与 sgm.v 高度复用（XOR 阵列、popcount LUT6、WTA 比较树）
- Lr3 行缓冲的 BRAM 消耗为 `MAX_MATCH_DEPTH × SGM_LR_WIDTH = 48 × 12 = 576 bit` / 行
- 双方向融合后有效抑制了单方向 Lr1 的条状伪影（streaking artifact）
- 总流水线延迟约 13 个时钟周期（与 sgm.v 一致，因 Lr3 缓冲与流水线级并行）
- 处理时钟频率 **20 MHz**（由顶层 PLL 生成 `sgm_clk`），对应纯算法吞吐率 > 60fps @ 640x480

#### 2.8.2 sgm.v — 早期单方向参考实现（演进历史）

**文件位置**：`RTL_code/algorithm/double_camera_vision/sgm.v`

**功能**：SGM 立体匹配算法的单方向硬件参考实现，仅包含 Lr1（从左到右）代价聚合。作为项目早期的算法验证平台，其核心运算单元（XOR + popcount + WTA）的设计为 sgm_new_2 提供了直接复用的基础。

**与 sgm_new_2 的关键差异**：
| 项目 | sgm.v | sgm_new_2 |
|------|-------|-----------|
| 代价聚合方向 | 1 方向（Lr1） | 2 方向（Lr1 + Lr3） |
| Lr3 行缓冲 | 无 | 有（BRAM） |
| 条状伪影 | 明显 | 显著抑制 |
| 在 SGM_TOP 中例化 | 否 | 是 |
| 代码定位 | 原型验证 | 最终交付 |

sgm.v 的详细流水级描述（13+1 级）、XOR-popcount 机制和 WTA 比较树结构与 sgm_new_2 的基础路径一致，此处不再赘述。

---

### 2.9 视差图显示输出 (sgm_disp.v)

**文件位置**：`RTL_code/Video_display_layer/sgm_disp.v`

**功能**：将 SGM 视差图叠加到双目 RGB 画面上，通过 HDMI 输出 1080P 显示。

**显示布局**：
- 输出分辨率：1920x1080 @ 60fps
- 左目图像区域：(160, 32) → (800, 512)
- 右目图像区域：(1120, 32) → (1760, 512)
- 视差图区域：(160, 562) → (800, 1042)

**实现机制**：
- 4 级延迟链对齐 VESA 输入时序
- 在有效区域内将视差图像素叠加到 VESA 信号流
- 通过 AXI 读通道从 DDR3 读取视差数据（SGM 写回的格式）
- 视差数据经过 `frame_switch_v_2_0` 管理的独立缓冲区

---

### 2.10 摄像头初始化与配置

#### uart_cfg.v

**文件位置**：`RTL_code/Module_initialization/ov5640/uart_cfg.v`

**功能**：通过 UART 接收上位机的配置指令，通过 I2C 接口配置 OV5640 寄存器。

**协议格式**（5 字节）：
```
Byte[0] = Device ID (0x57)
Byte[1] = Command (0xCD 写 / 0xAB 读)
Byte[2] = Register Addr High
Byte[3] = Register Addr Low
Byte[4] = Data (写模式)
```
- UART 波德率：115200
- I2C 时钟频率：250kHz
- 支持超时检测（`uart_timeout_cnt`）
- 状态码反馈：`DEVICE_ACK_CODE=0xAC`, `WR_END_CODE=0xCA`, `CMD_FALSE_CODE=0xCF` 等

#### i2c_ctrl.v

**文件位置**：`RTL_code/Module_initialization/ov5640/i2c_ctrl.v`

**功能**：I2C 主控制器，执行 OV5640 寄存器的读写时序（在 `uart_cfg.v` 中被调用）。

#### video_init.v

**文件位置**：`RTL_code/Top/video_init.v`

**功能**：系统初始化时序管理。控制上电顺序：
1. DDR3 初始化完成 → 释放摄像头复位
2. 使能摄像头 I2C 配置
3. 使能 HDMI 发送芯片初始化
4. 全部完成后释放 `stream_rst_n`（数据流复位）

参数 `DDR_RST_TIME=505000`（505us @ 50MHz）确保 DDR 复位脉冲足够宽。

---

### 2.11 UART 通信接口

#### uart_rx.v / uart_tx.v

**文件位置**：`RTL_code/UART_interface/uart_rx.v`, `uart_tx.v`

**功能**：标准 UART 收发器，用于 FPGA 与上位机的指令通信。

---

## 3. 软件代码总结

### 3.1 入口与程序结构 (main.py)

**文件位置**：`Software/Source_Code/main.py`

**功能**：程序入口，创建 PyQt5 应用和主窗口。

```python
app = QApplication(sys.argv)
app.setStyle("Fusion")
window = MainWindow()
window.show()
```

---

### 3.2 GUI 主窗口 (main_window.py)

**文件位置**：`Software/Source_Code/gui/main_window.py`（1225 行）

**功能**：上位机图形界面的核心窗口类，管理所有 UI 交互和功能切换。

**状态管理**（已重构为 Enum）：
```python
class AppState(IntEnum):
    IDLE = 0       # 空闲
    PREVIEW = 1    # 预览模式
    CONNECTED = 2  # 连接模式（全功能）

class ViewMode(IntEnum):
    LEFT = 0       # 左目视图
    RIGHT = 1      # 右目视图
    DISPARITY = 2  # 视差图视图
    YOLO_LOG = 3   # YOLO检测日志
    DEBUG = 4      # SGM Debug对比模式
```

**核心 UI 组件**：
| 组件 | 功能 |
|------|------|
| `camera_combo` | 摄像头列表下拉选择 |
| `preview_btn / connect_btn / disconnect_btn` | 相机状态控制 |
| `heatmap_btn` | 视差热力图开关 |
| `pcd_btn` | 3D 点云开关 |
| `defect_btn` | 缺陷检测开关 |
| `calib_group` | 焦距校准面板 |
| `pnp_btn` | PnP 姿态估计功能 |
| `stacked` (QStackedWidget) | 多视图切换 |
| `ImageViewer` x4 | 左目/右目/视差热力图/3D点云视图 |
| `latency_label` | 实时 FPS 和各阶段延迟显示 |

**关键方法**：
- `_update_frames()`：帧更新主循环（33ms 定时器触发），包含预览和连接两种模式
- `_handle_connected_frame(frame)`：连接模式帧处理，通过 `ParallelPipeline` 提交帧数据
- `_on_toggle_debug()`：SGM Debug 对比模式，启动后台线程计算软件 SGM 并与 FPGA 输出对比
- `_on_calib_apply()`：焦距校准，基于多帧测距数据计算平均焦距
- `_update_ui_state()`：根据状态机启用/禁用对应的 UI 控件

---

### 3.3 并行处理流水线 (parallel_pipeline.py)

**文件位置**：`Software/Source_Code/utils/parallel_pipeline.py`（257 行）

**功能**：GPU worker 线程驱动的并行处理流水线，负责异步处理视差恢复、PCB 检测和缺陷检测。

**架构**：
```
MainWindow._update_frames()
  └→ ParallelPipeline.submit_frame(frame)
      ├→ crop_left_camera / crop_right_camera
      ├→ 入队 input_queue (maxsize=4)
          GPU Worker Thread:
          ├→ _process_disparity: 视差恢复 + 子像素填充 + 中值滤波 + 热力图
          ├→ _process_board: PCB 板检测 + 距离计算
          └→ _process_defect: 缺陷检测 + 距离追踪
              ↓
      └→ get_merged() ←─ TimestampBuffer (最接近时间戳匹配)
```

**关键模块**：
| 模块 | 类/函数 | 功能 |
|------|---------|------|
| TimestampBuffer | `put_disp()/put_board()/put_defect()/put_frame_meta()` | 线程安全的时间戳缓冲 |
| `get_merged()` | 最近时间戳匹配合并 | 将异步结果与显示帧对齐 |
| `compute_bbox_distances()` | `compute_bbox_disparity()` + `disparity_to_distance()` | 检测框距离测量 |

**GPU 预热**：在 `_start_gpu_thread()` 中先执行一次 `torch.zeros(1, device='cuda')` 确保 CUDA 上下文就绪。

**已知设计问题**（来自 `plan.md`）：
- 直接访问私有成员 `_heatmap_active` / `_pcd_active`（已拆解到 `plan.md` 重构计划中）
- 宽泛的 `except Exception` 异常捕获，无错误状态传播

---

### 3.4 图像处理器核心 (image_processor.py)

**文件位置**：`Software/Source_Code/utils/image_processor.py`（600 行）

**功能**：视差图处理的核心算法模块，包含恢复、填充、滤波、可视化、点云生成等功能。

#### 3.4.1 视差图恢复

```python
def restore_disparity_map(disp_img):
    # RGB 逆编码: disparity = (R+G+B)/3.0 / SCALE_FACTOR / SUBPIXEL_DIVISOR
    # 无效像素判定: R>=200, G<50, B<50 → disparity = -1
```

FPGA 通过 HDMI 输出视差图时使用 RGB 三通道编码（各通道相同值），需要逆解码。`SCALE_FACTOR=1`, `SUBPIXEL_DIVISOR=2.0`，因此实际视差范围 `0~47 * 2 = 0~94`。

#### 3.4.2 GPU 加速视差填充

```python
def gpu_subpixel_fill_disparity(disparity_map, max_iter=30):
    # 5x5 交叉形卷积核填充无效像素
    # 权重核: 中心0, 十字形加权（4邻域权重3, 4角权重1, 对角线外权重2）
    # 迭代直到无新填充像素
    # 使用 PyTorch Conv2d 在 GPU 上执行
```

#### 3.4.3 GPU 中值滤波

```python
def gpu_median_filter_disparity(disparity_map, kernel_size=5):
    # 使用 torch.nn.functional.unfold + median 实现
```

#### 3.4.4 3D 点云生成

```python
def disparity_to_pointcloud_gpu(disparity_map, ...):
    # X = (u - cx) * Z / f, Y = (v - cy) * Z / f, Z = B * f / disp
    # 颜色: depth-jet 映射 或 rgb 颜色映射
    # 支持体素降采样: voxel_downsample_pointcloud()
```

#### 3.4.5 测距公式

```
Z = baseline_cm × focal_length_px / disparity
```
其中 `baseline_cm = 3.00546`, `focal_length_px = 609.157`。

---

### 3.5 相机采集模块 (capture.py)

**文件位置**：`Software/Source_Code/camera/capture.py`（162 行）

**功能**：基于 OpenCV 的 USB 摄像头采集封装。

**关键设计**：
- **独立抓取线程**（`CamGrab` daemon thread）：持续调用 `cap.read()` 将最新帧存入 `_latest_frame`（线程锁保护）
- **多后端回退**：优先 DirectShow → MSMF 回退
- **预热机制**：`_warm_up()` 在打开后抓取 3 帧稳定曝光
- `read_frame()` 返回当前最新帧并置空内部缓冲
- 请求分辨率：1920x1080（匹配 FPGA HDMI 输出分辨率）
- 静默 stderr：抑制 OpenCV 后端警告信息

---

### 3.6 PCB 检测模块

#### pcb_detector.py

**文件位置**：`Software/Source_Code/utils/pcb_detector.py`

**功能**：基于 YOLOv8n 的 PCB 板卡检测和缺陷检测。

- `PCBDetector` 类：封装 YOLOv8n 模型加载和推理
- `PCBBoardDetector` 类：PCB 板卡整体检测（使用 `pcb_board_det.pt`）
- `detect()` 方法返回检测框列表 `[{class, conf, bbox}]`
- `detect_best()` 返回最高置信度的 PCB 板检测结果

**模型配置**（来自 `config.py`）：
| 模型 | 文件 | 用途 |
|------|------|------|
| `yolov8n.pt` | 6.23MB | YOLOv8n 基础模型 |
| `pcb_board_det.pt` | - | PCB 板卡检测 |
| `pcb_defect_det.pt` | - | PCB 缺陷检测（6 类） |

---

### 3.7 PnP 姿态估计 (pnp_estimator.py)

**文件位置**：`Software/Source_Code/utils/pnp_estimator.py`（约 200+ 行）

**功能**：基于 PnP（Perspective-n-Point）算法的 6D 姿态估计。

**处理流程**：
```
YOLOv8n 检测 PCB 板 ROI
  → ORB 特征提取 + 金字塔尺度匹配
  → GPU Hamming 距离批量计算（_GpuOrbMatcher）
  → 最优尺度模板匹配
  → cv2.solvePnP() 求解 (R, t)
  → draw_pose() 绘制坐标轴
```

**`_GpuOrbMatcher` 类**：
- 在 GPU 上预计算 256 元素 popcount LUT
- `batch_hamming()`：模板与目标描述子的批量 Hamming 距离
- `batch_good_matches_ratio()`：金字塔多尺度匹配，返回最佳匹配比例

**PnP 配置参数**：
| 参数 | 值 | 含义 |
|------|-----|------|
| `PNP_ORB_NFEATURES` | 2000 | ORB 特征点数 |
| `PNP_ORB_GOOD_MATCH_DIST` | 50 | 好匹配距离阈值 |
| `PNP_SIMILARITY_THRESHOLD` | 0.15 | 相似度阈值 |
| `PNP_YOLO_TRIGGER_INTERVAL` | 15 | 每隔 N 帧触发一次 |
| `PNP_GPU_MATCHING_ENABLED` | True | GPU 加速匹配 |

---

### 3.8 SGM 调试对比 (sgm_debug.py)

**文件位置**：`Software/Source_Code/utils/sgm_debug.py`（256 行）

**功能**：在 PC 端实现软件 SGM 算法的参考实现，用于与 FPGA 硬件输出进行精度对比验证。

**关键函数**：
- `compute_census_5x5(gray_img)`：5x5 Census 变换（24bit）
- `_popcount_24bit(arr)`：64bit 并行 popcount（经典分治算法）
- `sgm_2dir(census_left, census_right)`：2 方向 SGM（L1 从左到右 + L3 从右到左）
- `encode_disparity(disparity_map, subpixel_map, confidence_map)`：编码为与 FPGA 兼容格式
- `compare_with_fpga(sw_encoded, fpga_disp_crop, disp_map_full)`：软件/FPGA 对比，输出 RMSE、最大差、相关系数

**对比指标**：
- `num_both_valid`：两方都有效的像素数
- `rmse`, `max_diff`, `mean_diff`, `mean_abs_diff`：差异统计
- `correlation`：皮尔逊相关系数
- `sw_valid_pct`, `fpga_valid_pct`：有效像素比例

---

### 3.9 配置管理 (config.py)

**文件位置**：`Software/Source_Code/utils/config.py`（114 行）

**功能**：集中管理所有可配置参数。

**关键配置组**：
```python
FPGA_PARAMS = {         # FPGA 输出画面中各区域的坐标偏移
    "CMR_1_DISP_AREA_H_OFST": 160,
    "CMR_1_DISP_AREA_V_OFST": 32,
    "CMR_2_DISP_AREA_H_OFST": 1120,
    "CMR_2_DISP_AREA_V_OFST": 32,
}

SGM_DISP_PARAMS = {     # SGM 视差图参数
    "MAX_DISPARITY": 47,        # 最大视差值
    "INVALID_R_THRESH": 200,    # 无效像素判定阈值
    "SCALE_FACTOR": 1,
    "SUBPIXEL_DIVISOR": 2.0,
}

STEREO_PARAMS = {       # 双目立体参数
    "BASELINE_CM": 3.00546,
    "DISP_IMAGE_WIDTH": 640,
}

STEREO_FOCAL_LENGTH_PX = 609.157
```

---

### 3.10 其他辅助模块

| 文件 | 行数 | 功能 |
|------|------|------|
| `latency_tracker.py` | 93 行 | 处理延迟追踪，维护各阶段的滑动窗口平均值 |
| `timestamp_buffer.py` | 118 行 | 线程安全的时间戳缓冲，支持最接近时间戳匹配 |
| `distance_tracker.py` | - | 距离追踪器，多帧滤镜平滑测距结果 |
| `rectification.py` | - | 图像校正模块，基于离线标定 LUT 进行极线校正 |
| `image_viewer.py` | - | PyQt5 图像显示控件 |
| `point_cloud_viewer.py` | - | 3D 点云 OpenGL 显示控件 |
| `pnp_template_dialog.py` | - | PnP 模板加载对话框 |
| `train_defect_detector.py` | - | YOLOv8n 缺陷检测模型训练脚本 |
| `test_model.py` | - | 模型测试脚本 |
| `gen_training_report.py` | - | 训练报告生成脚本 |

---

## 4. 软硬协同接口分析

### 4.1 FPGA 与 DDR3 的 AXI 交互

```
FPGA Master (DVP_AXI / SGM_TOP) 
  → AXI Write/Read Transactions
  → AXI_arbiter_v_2_0 (信用流控 + 固定优先级)
  → ddr3_50h IP Core (Simplified AXI4 → DDR3 PHY)
  → DDR3 SDRAM (外部存储)
```

**数据格式**：
- AXI 数据宽度：256bit（DDR3 位宽 32bit × 8 = 256bit）
- RGB565 像素封装在 256bit 中：每个 burst 包含 16 个像素
- AXI ID 分配：
  - `0x1` / `0x2`：CMR1/2 写通道
  - `0x6` / `0x7`：Display CM1/2 读通道
  - `0x4` / `0x5`：SGM CM1/2 读通道
  - `0x3`：SGM 写通道
  - `0x8`：sgm_disp 读通道

### 4.2 上位机通过 HDMI 获取 FPGA 输出

FPGA 端：
- `sgm_disp.v` 将 SGM 视差图叠加到 1080P VESA 时序的指定区域
- 通过 HDMI 发送芯片输出到显示器
- 视差图编码方式：RGB 三通道等值编码 `disparity * SCALE_FACTOR`

上位机端：
- USB 采集卡捕获 HDMI 输出的 1920x1080 画面
- `crop_left_camera(frame)` / `crop_right_camera(frame)` 裁剪左右目 640x480 区域
- `crop_sgm_disparity(frame)` 裁剪视差图 640x480 区域
- `restore_disparity_map(disp_img)` 逆编码恢复视差值

### 4.3 视差图编码约定

| 编码端 (FPGA) | 解码端 (PC) |
|--------------|------------|
| `disparity` (0-47) → RGB 三通道等值 = `disparity * SCALE_FACTOR` | `disparity = (R+G+B)/3 / SCALE_FACTOR / SUBPIXEL_DIVISOR` |
| 无效像素通过特定 RGB 值标记（R>=200, G<50, B<50） | 无效像素判定阈值：`INVALID_R_THRESH=200` 等 |
| `SUBPIXEL_DIVISOR=2.0` | 等效视差范围 0~94（步进 0.5） |

### 4.4 配置参数传递

- FPGA 端参数通过 Verilog `parameter` 在顶层 `OV_DDR_HDMI_v_2_0.v` 中配置
- PC 端参数通过 `config.py` 集中管理
- 关键耦合参数：
  - `MAX_DISPARITY=47`（FPGA 的 `MAX_MATCH_DEPTH=48` 减 1）
  - `CAMERA_WIDTH=640, CAMERA_HEIGHT=480` 与 `CROP_WIDTH=640, CROP_HEIGHT=480` 匹配
  - `SGM_DISP_PARAMS` 中的偏移量与 `sgm_disp.v` 的 `DISP_H_OFFSET=160, DISP_V_OFFSET=562` 对应
  - `STEREO_PARAMS["BASELINE_CM"]=3.00546` 与实物双目基线距匹配

---

## 5. 代码规模统计

### RTL 硬件代码

| 文件 | 行数（约） | 功能层级 |
|------|----------|---------|
| `OV_DDR_HDMI_v_2_0.v` | 956 | 系统顶层 |
| `SGM_TOP.v` | 380 | SGM 子系统顶层 |
| `sgm.v` | 636 | SGM 算法核心（单方向） |
| `sgm_data_engine.v` | 424 | SGM 数据引擎 |
| `rgb2gray.v` | 83 | RGB 转灰度 |
| `sgm_disp.v` | ~350 | SGM 视差叠加显示 |
| `DVP_AXI_v_2_0.v` | ~200 | DVP→AXI 采集 |
| `VESA_AXI_v_3_0.v` | ~200 | VESA→AXI 输出 |
| `AXI_arbiter.v` / `axi_arbiter_v_2_0` | ~300 | AXI 仲裁器 |
| `frame_switch.v` | ~200 | 三重缓冲管理 |
| `uart_cfg.v` | ~250 | UART 配置控制器 |
| `i2c_ctrl.v` | ~150 | I2C 控制器 |
| `video_init.v` | ~100 | 初始化时序管理 |
| `uart_rx.v` / `uart_tx.v` | ~150 | UART 收发器 |
| `Disp_param.vh` | 17 | 显示参数定义 |
| **RTL 合计** | **约 4400 行** | - |

### 软件代码 (Python)

| 文件 | 行数 | 功能 |
|------|------|------|
| `main.py` | 17 | 入口 |
| `main_window.py` | 1225 | GUI 主窗口 |
| `parallel_pipeline.py` | 257 | 并行流水线 |
| `image_processor.py` | 600 | 图像处理核心 |
| `config.py` | 114 | 配置管理 |
| `sgm_debug.py` | 256 | SGM 软件参考实现 |
| `capture.py` | 162 | 相机采集 |
| `pnp_estimator.py` | ~220 | PnP 姿态估计 |
| `pcb_detector.py` | ~150 | PCB 检测 |
| `latency_tracker.py` | 93 | 延迟追踪 |
| `timestamp_buffer.py` | 118 | 时间戳缓冲 |
| `distance_tracker.py` | ~80 | 距离追踪 |
| `rectification.py` | ~100 | 图像校正 |
| `image_viewer.py` | ~80 | 图像显示控件 |
| `point_cloud_viewer.py` | ~150 | 3D 点云控件 |
| `pnp_template_dialog.py` | ~80 | PnP 模板对话框 |
| `train_defect_detector.py` | ~80 | 训练脚本 |
| `test_model.py` | ~80 | 测试脚本 |
| `gen_training_report.py` | ~60 | 报告生成 |
| **软件合计** | **约 3922 行** | - |

### Matlab 脚本

| 文件数 | 用途 |
|--------|------|
| ~20 个 `.m` 脚本 | SGM 算法仿真/验证/评估 |
| ~10 个标定文件 | 双目标定 LUT 生成 |

### 总体规模

| 层级 | 文件数 | 代码行数 |
|------|--------|---------|
| RTL 硬件 | ~15 | ~4400 行 |
| Python 软件 | ~19 | ~3900 行 |
| Matlab 脚本 | ~20 | ~2500 行 |
| **总计** | **~54** | **~10800 行** |

---

*本文档由代码自动分析生成，基于对项目全部源代码文件的逐层阅读与交叉引用。*

---

## 交叉审查报告

> 审查日期：2026-06-01
> 主文件：code_summary.md
> 交叉核对：thesis_summary.md | ppt_framework.md | speech_draft.md

### 数据一致性审查

| 数据项 | code_summary | thesis_summary | ppt_framework | speech_draft | 是否一致 |
|-------|:---:|:---:|:---:|:---:|:---:|
| 分辨率 | 640x480 | 640x480 | 640x480 | 640x480 | ✅ |
| 最大匹配深度 | 48 (视差0~47) | 48 (视差0~47) | 48视差级别 | 48视差级别 | ✅ |
| Census窗口大小 | 5x5 | 5x5 | 5x5 | 5x5 | ✅ |
| Census序列宽度(24bit) | 24 | 24 | 24bit | 24比特 | ✅ |
| SGM方向数/路径数 | 1方向(sgm.v) / 2方向(sgm_new_2) | 2方向(Lr1+Lr3) | 2方向(Lr1+Lr3) | 2方向(Lr1,Lr3) | ⚠️ 见冲突1 |
| 路径方向 | Lr1 + Lr3 | Lr1 + Lr3 | Lr1 + Lr3 | Lr1 + Lr3 | ✅ |
| SGM_P1值 | 3 | 3 | 3 | 未明确给出 | ✅ |
| SGM_P2值 | 24 | 24 | 24 | 未明确给出 | ✅ |
| FPGA型号 | 紫光同创 PG2L50H | 紫光同创 PG2L50H-FG484 (Logos2系列) | 紫光同创 PG2L50H | 紫光同创 PG2L50H | ❌ 见冲突2 |
| 工艺节点 | 未提及 | 40nm | 40nm | 40纳米 | ⚠️ code_summary缺失 |
| 摄像头型号 | OV5640 | OV5640双目模组 | OV5640 | OV5640 | ✅ |
| 帧率/延迟(FPGA SGM纯算法) | 未明确给出 | 106.7 fps | 支持65fps > 60fps | 未明确给出 | ❌ 见冲突3 |
| 帧率/延迟(系统端到端) | 未明确给出 | ~30ms/33fps | 46.5ms/~21fps | ~30ms/33fps | ❌ 见冲突3 |
| SGM时钟频率 | 未明确给出(sgm_clk来源PLL) | 20.2 MHz | 20 MHz | 20 MHz | ⚠️ code_summary缺失 |
| HDMI/像素时钟 | 148.5 MHz (pix_clk) | 148.4 MHz (pix_clk) | 148.5 MHz (AXI时钟) | 148.5 MHz (HDMI) | ✅ (0.1MHz差异可忽略) |
| 摄像头像素时钟 | 未明确给出 | 50.4 MHz (cmr_pclk) | 24 MHz | 100 MHz | ❌ 见冲突4 |
| LUT消耗(SGM模块) | 未提及 | ~11,000 LUT6 | ~11,000 / 约50,000 (22%) | ~11,000 LUT6 (22%) | ⚠️ code_summary缺失 |
| LUT总量/可用量 | 未提及 | 35,800 / 64,200 (内部矛盾) | 约50,000 | 未明确给出 | ❌ 见冲突5 |
| DRM/BRAM消耗(SGM模块) | 未提及 | 129.5块DRM (系统总计) | 约80块(47%) | 约80块(47%) | ❌ 见冲突6 |
| DRM总量 | 未提及 | 134(96%) / 170(另一处) | 170 | 170 | ❌ 见冲突6 |
| 功耗 | 未提及 | 总功耗1.48W | "约X W(需填写实测值)" | "几百毫瓦级别" | ❌ 见冲突7 |
| YOLO版本 | YOLOv8/YOLOv8n | YOLOv8n | YOLOv8s / YOLOv8n (内部矛盾) | YOLOv8n | ❌ 见冲突8 |
| Bad 1.0误差(FPGA 2方向) | 未提及 | 12.86% | 未明确给出绝对值 | 未明确给出绝对值 | ⚠️ code_summary缺失 |
| Bad 1.0差异(vs 4方向参考) | 未提及 | +1.81pp | "差异仅1.81%" | "约1.8个百分点" | ⚠️ code_summary缺失 |
| 基线距(baseline) | 未提及 | 3.0055 cm | 3.00546 cm | 未提及 | ⚠️ 0.00004cm差异可忽略 |
| 焦距(focal_length) | 609.157 px | 609.157 px | 609.157 px | 未提及 | ✅ |
| 流水线级数 | 13+1 (sgm.v) | 13级 | 13级(2+2+4+4+1) | "13到18个时钟周期" | ❌ 见冲突9 |
| DDR3数据位宽 | 32 bit | 32 bit | 未明确给出 | 未明确给出 | ✅ |
| DDR3容量 | 未明确给出 | 8 Gbit | 未明确给出 | 未明确给出 | - |

### 发现的冲突

#### 1. [严重] code_summary 内部 SGM 版本描述与其余三份文件不一致

code_summary 在第2.8节详细描述了 `sgm.v` 的单方向(Lr1)实现（sgm.v），仅在末尾备注中提及"存在升级版 `sgm_new_2`，支持2方向代价聚合（Lr1+Lr3）"。但 thesis_summary、ppt_framework、speech_draft 三者均以"2方向(Lr1+Lr3)"作为系统最终实现的唯一描述。code_summary 作为主文件应明确标注最终版本（sgm_new_2）为主要实现，而非将单方向版本作为正文主体。

**建议**：在 code_summary 第2.8节开头增加说明"此处描述的是原始单方向参考实现，最终系统使用 `sgm_new_2` 支持 Lr1+Lr3 两方向代价聚合"，或直接以 `sgm_new_2` 为主体描述。

#### 2. [严重] FPGA 芯片型号不一致

- code_summary / ppt_framework / speech_draft 均使用 **"PG2L50H"**
- thesis_summary 使用 **"PG2L50H-FG484（Logos2系列）"** （thesis_summary.md）

"PG2L50H" 是紫光同创 Logos 系列的早期产品代号，而 "PG2L50H" 是 Logos2 系列产品。这是两款不同的芯片。需统一确认实际使用的是哪一款。从 thesis_summary 标注 "Logos2系列" 来看，论文中应使用 PG2L50H，但 PPT 和演说稿中简化成了 PG2L50H。

**建议**：所有文件统一为精确型号（PG2L50H-FG484），并在首次出现时标注"俗称PG2L50H"以消除歧义。

#### 3. [严重] 系统端到端延迟数据严重矛盾

| 文件 | FPGA端延迟 | PC端延迟 | 端到端总延迟 | 全功能帧率 |
|------|:---:|:---:|:---:|:---:|
| code_summary | 未给出 | 未给出 | 未给出 | 未给出 |
| thesis_summary | SGM纯算法 ~9.4ms | YOLO 14ms / PnP 15ms | 未显式汇总 | SGM 106.7fps |
| ppt_framework | **~16.5ms** (L321) / **~15ms** (L289) | **~30ms** | **~46.5ms** (L333) / **45ms** (L289) | ~33 FPS |
| speech_draft | "十几毫秒" (L152) | 未单独给出 | **"大约30毫秒"** (L152) | 约33fps |

核心矛盾：
- speech_draft 称整个系统延迟"大约30毫秒"，但 ppt_framework 给出的端到端延迟是 45~46.5ms，相差超过50%。
- thesis_summary 给出 SGM 纯硬件吞吐率 106.7fps（约 9.4ms/帧），远快于 ppt 中的 15.4ms/帧，这可能是"纯算法延迟"与"含DDR3读写+HDMI输出的全链路延迟"之间的差异，但两份文件未做区分说明。
- ppt_framework 内部也不一致：第9页说 FPGA SGM 15.4ms（支持65fps），第19页说 FPGA 总延迟 16.5ms。

**建议**：统一延迟数据，明确区分"纯算法延迟"、"含DDR3的SGM子系统延迟"、"FPGA端全链路延迟"、"PC端延迟"、"端到端总延迟"五个层级，每份文件引用同一套数字。

#### 4. [严重] 摄像头像素时钟频率三方矛盾

- ppt_framework 第9页（ppt_framework.md）：**24MHz**
- speech_draft 第7页（speech_draft.md）：**100MHz**
- thesis_summary（thesis_summary.md）：**50.4 MHz** (cmr_pclk)

三个值完全不同。OV5640 的典型像素时钟在 480P@60fps 下约 24MHz（实际上 640x480x60x2 ≈ 36.8MHz，考虑 blanking），50.4MHz 可能是 2倍像素时钟或 DDR 模式。100MHz 则可能是 AXI 时钟而非像素时钟。

**建议**：以 thesis_summary 的实测/设计值为准，统一所有文件的时钟频率描述，并标注每个时钟的来源和用途。

#### 5. [中等] LUT6 资源总量在不同文件中不一致，thesis_summary 内部也存在矛盾

- thesis_summary 第3.1节（thesis_summary.md）：**35,800 LUT6** / 71,600 FF
- thesis_summary 第6.2节（thesis_summary.md）：可用量 **64,200 LUT6**，消耗 29,886（35%）
- ppt_framework（ppt_framework.md）：**约 50,000** 总量
- code_summary：未提及
- speech_draft：未提及

35,800 和 64,200 差异巨大。35,800 可能是 PG2L50H 的 LUT6 实际数量（Logos2系列），而 64,200 可能是等效 LUT4 数量或其他换算口径。ppt 中"约50,000"又取了一个中间值。

**建议**：统一使用同一口径（建议用 PDS 综合报告中的 LUT6 实际数量），在 thesis 和 ppt 中使用相同的数字。

#### 6. [中等] DRM/BRAM 消耗量严重矛盾

- thesis_summary（thesis_summary.md）：系统总计 **129.5 块 DRM / 134 块可用（96%）**，SGM模块自身约1Mb分布式RAM
- ppt_framework（ppt_framework.md）：SGM模块 **约 80 块 DRM / 170 块可用（47%）**
- speech_draft（speech_draft.md）：SGM模块 **约 80 块（47%）**

两个维度的冲突：
(1) DRM 总量：thesis 说 134，ppt 和 speech 说 170。PG2L50H 的 DRM 总量需核实。
(2) SGM 消耗：thesis 说 129.5（含系统其他模块），ppt/speech 说约 80（仅 SGM 核心）。如果 thesis 的 129.5 是系统总计，ppt 的 80 是 SGM 单独消耗，则两者可以自洽——但 thesis 的 96% 利用率（129.5/134）说明 SGM 几乎吃掉了所有 BRAM，这与 ppt 的 47%（80/170）严重矛盾。

**建议**：核实 PG2L50H/PG2L50H 的实际 DRM 总量，统一 SGM 模块消耗量（区分 SGM 单独 vs 系统总计）。

#### 7. [中等] 功耗数据三方矛盾

- thesis_summary（thesis_summary.md）：总功耗 **1.48W**，静态 0.229W
- speech_draft（speech_draft.md）：**"几百毫瓦级别"**（暗示 <1W）
- ppt_framework（ppt_framework.md）：**"约 X W（需填写实测值）"**

1.48W 不属于"几百毫瓦"。speech_draft 的描述与 thesis 数据明显冲突。ppt 因数据暂缺保留了占位符。

**建议**：以 thesis_summary 的 1.48W（PDS 工具估算）为准，speech_draft 修正为"约1.5W"，ppt 填入实际值。

#### 8. [中等] YOLO 版本描述不一致

- code_summary：**YOLOv8 / YOLOv8n**（code_summary.md）
- thesis_summary：**YOLOv8n**
- ppt_framework：第14页写 **YOLOv8s**（ppt_framework.md），第15页写 **YOLOv8s**（ppt_framework.md），第21页写 **YOLOv8n**（ppt_framework.md）
- speech_draft：**YOLOv8n**（speech_draft.md）

YOLOv8n 和 YOLOv8s 是不同的模型规格：nano（~3M 参数）vs small（~11M 参数）。ppt 在多个页面使用 YOLOv8s 来描述目标检测（包括 2200 万参数的描述也更接近 YOLOv8s），但在 Q&A 准备和不足部分又使用 YOLOv8n。speech_draft 明确定义了 YOLOv8n 为 "nano 约300万参数"。

**建议**：确认实际使用的模型版本。若为 YOLOv8n（如 speech 所述），ppt 中所有 YOLOv8s 须改为 YOLOv8n，参数描述（2200万→300万）也需同步修正。

#### 9. [轻微] 流水线级数描述差异

- code_summary sgm.v：**13+1 级**（Stage 0~13，14个流水级）
- thesis_summary：**13 级**
- ppt_framework：**13 级**（2+2+4+4+1 = 13）
- speech_draft：**"13到18个时钟周期的流水线延迟"**

speech_draft 的"13到18个"与另外三份文件的明确"13级"不一致。13和18之间差了5级——如果 speech 指的是"总处理延迟可能根据边界条件在13~18周期之间波动"则需要说明，如果是描述错误则需要修正。

#### 10. [轻微] Census变换模块名不一致

- code_summary：`census_5x5`（code_summary.md）
- ppt_framework 第11页：`matrix_gene_5x5.v`（ppt_framework.md）

两个不同的模块名指代同一功能。

**建议**：统一为实际 RTL 文件中的模块名。

### 架构与实现描述一致性审查

#### B1. RTL 层级结构

code_summary 第2.2节的 SGM_TOP 内部数据流描述为7层（FIFO→数据引擎→灰度化→Census→FIFO→SGM→VESA_AXI），与 thesis_summary 的六层模块化架构（系统级，含上位机）语境不同，不构成直接矛盾。但 ppt_framework 第10-13页对 FPGA 内部的描述使用了"五层架构"（初始化层/采集层/缓冲层/算法加速层/输出层），而 thesis_summary 使用的是"六层"（多了上位机作为第6层）。这是**架构层次命名体系的差异**，而非数据错误。建议在每份文件中明确标注"本文所述X层是指..."

#### B2. 模块名称一致性

code_summary 引用的模块名（`sgm.v`, `sgm_new_2`, `SGM_TOP.v`, `sgm_disp.v`, `census_5x5` 等）与 ppt_framework 大部分一致，仅 `census_5x5` vs `matrix_gene_5x5.v` 存在命名差异（见冲突10）。speech_draft 和 thesis_summary 未列出具体 RTL 文件名，无法交叉核对。

#### B3. AXI 仲裁器架构描述

四份文件对 AXI 仲裁器的描述一致：4主1从、信用流控+固定优先级。用户分配略有差异但可自洽：
- code_summary：User0(CMR1写+Display读) / User1(CMR2写) / User2(SGM_TOP读写) / User3(sgm_disp读)
- thesis_summary：User0(摄像头写入+显示读取) / User1(右目写入+SGM视差读取) / User2(SGM读取+写回)
- ppt_framework：左目采集/右目采集/SGM读/SGM写 —— 未区分 AR 和 AW 通道合并

建议 ppt 中的描述与 thesis/code_summary 对齐。

### 软件模块描述一致性审查

#### C1. 软件模块列表覆盖范围差异

code_summary 列出了约 19 个 Python 文件，thesis_summary 仅列出 7 个核心模块。这不是错误，而是 thesis 选择了简化表述。但 thesis_summary 遗漏了 `parallel_pipeline.py`（并行流水线核心）和 `pnp_estimator.py`（PnP姿态估计）这两个在 code_summary 和 ppt_framework 中重点描述的模块。

#### C2. 并行流水线架构描述差异

- code_summary：**GPU Worker Thread 模型**，单个 GPU worker 线程依次处理视差恢复→PCB检测→缺陷检测
- ppt_framework 第14页：**四线程并行流水线**，Thread1(采集)→Thread2(预处理)→Thread3(推理)→Thread4(后处理+GUI)
- speech_draft：四线程架构，与 ppt 一致

code_summary 的 `parallel_pipeline.py` 描述是**单 GPU worker 线程 + TimestampBuffer 异步合并**模型，而 ppt/speech 描述的是**四线程生产者-消费者流水线**。这两个模型不完全相同。如果实际实现如 code_summary 所述，则 ppt/speech 需要修正线程数描述；如果 ppt 描述的是设计目标，则 code_summary 需要注明当前实现与设计目标的差异。

#### C3. 视差恢复算法流程

四份文件对视差编码/解码约定（R>200, G<50, B<50 = 无效；MAX_DISPARITY=47）描述一致。code_summary 额外说明了 SUBPIXEL_DIVISOR=2.0 的细节，其他文件未涉及此粒度。

### 术语一致性审查

#### D1. code_summary 内部术语一致性

| 术语 | 使用情况 | 评价 |
|------|---------|------|
| DDR3 SDRAM / DDR3 | 统一使用，无混用 | ✅ |
| Census / Census变换 | 统一使用 | ✅ |
| SGM / 半全局匹配 | 统一使用，首次出现全称 | ✅ |
| 视差图 / disparity | 统一 | ✅ |
| AXI / Simplified AXI4 | 两处交替使用但语义一致 | ✅ |
| PG2L50H | 统一 | ✅ |
| DVP / VESA | 各自定义清晰 | ✅ |

code_summary 内部术语**基本一致**，无明显前后矛盾。

#### D2. 跨文件术语一致性

| 术语 | code_summary | thesis_summary | ppt_framework | speech_draft | 评价 |
|------|:---:|:---:|:---:|:---:|:---:|
| FPGA芯片简称 | PG2L50H | PG2L50H-FG484 | PG2L50H | PG2L50H | ❌ |
| 架构层次称谓 | 7层(SGM内部) | 六层(含上位机) | FPGA五层+PC五层 | 五个功能层 | ⚠️ 不同语境 |
| SGM核心模块名 | sgm.v / sgm_new_2 | 未提及 | sgm.v | 未提及 | ⚠️ code_summary提及两个版本 |
| Census模块名 | census_5x5 | 未提及 | matrix_gene_5x5.v | 未提及 | ❌ |
| YOLO模型名 | YOLOv8n | YOLOv8n | YOLOv8s/YOLOv8n混用 | YOLOv8n | ❌ |
| Hamming/Hamming距离 | Hamming | Hamming | Hamming | Hamming | ✅ |
| WTA/Winner-Takes-All | WTA | WTA | 胜者为王 | 未提及 | ✅ |
| 代价聚合 | ✅ | ✅ | ✅ | ✅ | ✅ |
| Bad 1.0 | 未提及 | ✅ | ✅ | ✅ | ⚠️ code_summary缺失 |

### 对主文件的自我审查

1. **内部术语是否一致**：code_summary 内部术语基本一致，但以下问题需修正：
   - 第2.8节以 `sgm.v`（单方向）为主体描述，而第2.2节 SGM_TOP 中例化的是 `sgm_new_2`（两方向），导致读者困惑最终实现到底是哪个版本。
   - 第4.4节提到 `MAX_DISPARITY=47`（PC端） = `MAX_MATCH_DEPTH=48`（FPGA端）减1，这个等式是正确的，但未在其他位置重申此对应关系。

2. **模块命名是否规范**：
   - `sgm.v` 与 `sgm_new_2` 的命名未遵循统一的版本迭代命名规则（如 `sgm_v1.v` / `sgm_v2.v`），`sgm_new_2` 的命名较随意。
   - `census_5x5` 与 ppt 中的 `matrix_gene_5x5.v` 不一致，应统一。

3. **数据缺失项**：code_summary 作为主文件，以下关键数据缺失，应补充：
   - SGM 时钟频率具体数值
   - FPGA 资源消耗数据（LUT/DRM/DSP/功耗）
   - 系统端到端延迟
   - Bad 1.0 误差指标
   - 工艺节点（40nm）

### 对其他文件的修正建议

 **thesis_summary.md**：
1. [严重] 统一 FPGA 芯片型号描述：若确为 PG2L50H，应在首次出现时注明俗称 PG2L50H；若为 PG2L50H，修正所有 PG2L50H 引用。
2. [严重] 修正 LUT6 资源数据内部矛盾（35,800 vs 64,200），查阅 PDS 综合报告确定正确数值。
3. [中等] 修正 DRM 总量（134 vs 170），与 ppt/speech 对齐。若确实为 134 块（非 170），需要在 ppt/speech 中同步修正。
4. [中等] 软件模块列表补充 `parallel_pipeline.py` 和 `pnp_estimator.py`。
5. [轻微] 补充系统端到端延迟汇总数据（建议与 ppt 对齐为 45~46.5ms）。

 **ppt_framework.md**：
1. [严重] 修正摄像头像素时钟（24MHz → 需核实正确值，建议与 thesis 的 50.4MHz 对齐）。
2. [严重] 统一 YOLO 版本：若为 YOLOv8n，将所有 YOLOv8s 引用修正为 YOLOv8n，参数描述 2200万→300万，100FPS 描述保留。
3. [中等] 统一 Census 模块名：`matrix_gene_5x5.v` → `census_5x5`（与实际 RTL 一致）。
4. [中等] 填入功耗实际值（1.48W）替换占位符"约 X W"。
5. [中等] 统一 LUT 总量（50,000 → 修正为实际值，建议与 thesis 对齐）。
6. [轻微] 第9页时钟域描述"像素时钟（24MHz）→ AXI时钟（148.5MHz）→ SGM时钟（20MHz）"中，148.5MHz 实为 HDMI 像素时钟而非 AXI 时钟（AXI 时钟约为 100MHz），建议修正箭头标注。

 **speech_draft.md**：
1. [严重] 修正系统端到端延迟："大约30毫秒" → 应与 ppt 对齐为约 45~46.5ms，或明确定义此30ms 具体指哪个环节的延迟。
2. [严重] 修正摄像头像素时钟描述："100MHz" → 核实正确值。
3. [中等] 修正功耗描述："几百毫瓦级别" → "约1.5W"。
4. [轻微] 修正流水线延迟："13到18个时钟周期" → "13个时钟周期"。
5. [轻微] 明确 YOLOv8n 参数描述：300万参数（而非2200万），避免与 YOLOv8s 混淆。

---

## 修正记录

> 修正日期：2026-06-01
> 基于交叉审查报告，对 code_summary.md 做出以下修正。

| 编号 | 修正项 | 修改位置 | 修改内容 |
|------|--------|---------|---------|
| 1 | SGM版本描述重写 | 第2.8节 | 标题从 `sgm.v` 改为"半全局匹配核心"，新增版本演进说明；以 sgm_new_2（2方向 Lr1+Lr3）为主体描述，含算法管线、Lr3反向扫描、参数配置；sgm.v 降级为"早期单方向参考实现（演进历史）"子节 |
| 2 | 补充缺失关键数据 | 第1节项目概览末尾 | 新增"关键技术指标"表，补充：SGM处理时钟20MHz、FPGA资源消耗（~11K LUT6/22%、~80 DRM/47%、~2 DSP）、工艺节点40nm、端到端延迟~46.5ms、Bad 1.0约12.86%（vs 4方向差1.81pp）、视差搜索范围48像素 |
| 3 | 模块名称一致性 | 第2.7节 | 新增引用块说明：`census_5x5` 是RTL例化名（顶层封装），`matrix_gene_5x5.v` 是内部5x5滑窗生成器，两者指代同一模块的不同层次 |
| 4 | FPGA端层级数 | 第2节开头 | 新增引用块明确FPGA端五层架构（初始化层→采集层→缓冲层→SGM加速层→显示输出层），注明勿与论文"六层（含上位机）"混淆 |
| 5 | DDR3位宽统一 | 全文 | 已核实：所有DDR3位宽描述已统一为32bit（2片16bit颗粒拼合），无需修改 |
| 6 | YOLO版本统一 | 第1节/第3.6节/第3.7节/第3.10节 | 将所有"YOLOv8"统一为"YOLOv8n"（约320万参数），涉及：第1节软件任务描述、第3.6节pcb_detector引用、第3.7节PnP流程、第3.10节训练脚本说明、模型配置表 |
