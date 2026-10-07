# 软件端设计问题与重构计划

> 本文档整理了上位机软件（Software/Source_Code/）中存在的设计问题，作为后续重构的依据。

---

## 1. 架构层面问题

### 1.1 God Class：MainWindow 过于庞大

**文件**: [gui/main_window.py](../Software/Source_Code/gui/main_window.py)
**行数**: 1225 行

`MainWindow` 类违反单一职责原则，同时承担了以下职责：

| 职责 | 所在方法 |
|---|---|
| UI 构建 | `_setup_ui()`, `_setup_menu()` |
| 相机管理（状态机） | `_on_preview_clicked()`, `_on_connect_clicked()`, `_disconnect()`, `_update_ui_state()` |
| 视差热力图显示 | `_on_toggle_heatmap()` |
| 3D 点云显示 | `_on_toggle_pcd()` |
| 手动测距 | `_on_toggle_measure()`, `_on_roi_selected()` |
| 缺陷检测集成 | `_on_defect_toggle()` |
| 焦距校准 | `_on_calibrate_toggle()`, `_on_calib_add_sample()`, `_on_calib_apply()` |
| PnP 模板加载 | `_on_add_pnp_template()` |
| SGM Debug 对比 | `_on_toggle_debug()`, `_process_sgm_debug()`, `_build_debug_visualization()` |
| 帧更新主循环 | `_update_frames()` |
| 性能监控显示 | `_update_latency_display()` |
| 相机列表异步加载 | `_refresh_camera_list_async()` |

**重构方案**：将 `MainWindow` 拆分为多个 Mixin 类或独立的控制器类：

- `MainWindow` — 仅保留核心窗口框架、UI 构建和相机管理
- `DisparityController` — 视差热力图 + 3D 点云 + 手动测距逻辑
- `DefectController` — 缺陷检测开关 + 日志管理 + PnP 模板
- `CalibrationController` — 焦距校准逻辑
- `SgmDebugController` — SGM Debug 对比模式

### 1.2 状态管理模式不健壮

**文件**: [gui/main_window.py:L55-L58](../Software/Source_Code/gui/main_window.py#L55-L58)

```python
STATE_IDLE = 0
STATE_PREVIEW = 1
STATE_CONNECTED = 2

VIEW_LEFT = 0
VIEW_RIGHT = 1
VIEW_DISPARITY = 2
VIEW_YOLO_LOG = 3
VIEW_DEBUG = 4
```

**问题**：使用原始整数常量而非 Python `Enum`，缺乏类型安全性和自文档化。

**重构方案**：改为使用 `enum.IntEnum` 或 `enum.Enum`：

```python
from enum import IntEnum

class AppState(IntEnum):
    IDLE = 0
    PREVIEW = 1
    CONNECTED = 2

class ViewMode(IntEnum):
    LEFT = 0
    RIGHT = 1
    DISPARITY = 2
    YOLO_LOG = 3
    DEBUG = 4
```

---

## 2. 封装与接口问题

### 2.1 直接访问私有成员

**文件**: [gui/main_window.py:L804](../Software/Source_Code/gui/main_window.py#L804)

```python
self._pipeline._heatmap_active = checked
```

**文件**: [gui/main_window.py:L822](../Software/Source_Code/gui/main_window.py#L822)

```python
self._pipeline._pcd_active = checked
```

**问题**：`MainWindow` 直接修改 `ParallelPipeline` 的私有成员 `_heatmap_active` 和 `_pcd_active`，违反了封装原则。`ParallelPipeline` 中这些成员已经定义为 `self._heatmap_active`（前缀下划线），意图为私有，但被外部直接修改。

**重构方案**：在 `ParallelPipeline` 中添加公共 setter 方法：

```python
def set_heatmap_active(self, active: bool) -> None:
    with self._state_lock:
        self._heatmap_active = active

def set_pcd_active(self, active: bool) -> None:
    with self._state_lock:
        self._pcd_active = active
```

然后在 `MainWindow` 中改为调用这些方法。

### 2.2 缺乏类型注解

**影响范围**：几乎所有 Python 文件。

| 文件 | 类型注解覆盖率 |
|---|---|
| `gui/main_window.py` | 几乎没有 |
| `utils/image_processor.py` | 几乎没有 |
| `camera/capture.py` | 几乎没有 |
| `utils/parallel_pipeline.py` | 部分有（仅 `ParallelPipeline` 的 `__init__`） |
| `utils/latency_tracker.py` | 完全没有 |

**重构方案**：为所有公共函数和方法添加完整的类型注解（使用 `typing` 模块），包括返回值类型。

---

## 3. 硬编码问题

### 3.1 视差最大值硬编码

**文件**: [gui/main_window.py:L570](../Software/Source_Code/gui/main_window.py#L570)

```python
disp_max = 47
```

**问题**：`config.SGM_DISP_PARAMS["MAX_DISPARITY"]` 已经定义了 `MAX_DISPARITY = 47`，但此处仍然硬编码。

**重构方案**：改为引用配置：

```python
disp_max = config.SGM_DISP_PARAMS["MAX_DISPARITY"]
```

### 3.2 窗口标题硬编码

**文件**: [gui/main_window.py:L152](../Software/Source_Code/gui/main_window.py#L152)

```python
self.setWindowTitle("Dual Camera 480P Viewer")
```

**问题**：分辨率信息硬编码在标题中，与 `config.CROP_WIDTH`/`config.CROP_HEIGHT` 不一致。

**重构方案**：使用配置常量动态生成标题。

### 3.3 最小刷新率硬编码

**文件**: [gui/main_window.py:L106](../Software/Source_Code/gui/main_window.py#L106)

```python
self._pcd_update_interval = 1.0 / max(config.PCD_PARAMS["REFRESH_RATE_HZ"], 1)
```

**问题**：最小值 `1` 硬编码，且零除保护逻辑内联。

**重构方案**：将最小值提取为命名常量或在 `config.py` 中定义。

### 3.4 5x5 卷积权重硬编码

**文件**: [utils/image_processor.py:L306-L312](../Software/Source_Code/utils/image_processor.py#L306-L312)

```python
weights_np = np.array([
    [0.0, 0.0, 1.0, 0.0, 0.0],
    [0.0, 2.0, 3.0, 2.0, 0.0],
    [1.0, 3.0, 0.0, 3.0, 1.0],
    [0.0, 2.0, 3.0, 2.0, 0.0],
    [0.0, 0.0, 1.0, 0.0, 0.0],
], dtype=np.float32)
```

**问题**：子像素填充的卷积核权重硬编码在函数内部，不易调整。

**重构方案**：提取为模块级常量或 `config.py` 中的配置项。

---

## 4. 异常处理问题

### 4.1 过于宽泛的异常捕获

**文件**: [utils/parallel_pipeline.py:L91-L92](../Software/Source_Code/utils/parallel_pipeline.py#L91-L92)

```python
except Exception:
    traceback.print_exc()
```

在 `_process_disparity`、`_process_board`、`_process_defect`、`update_pnp` 等关键方法中都存在同样的问题。

**问题**：
- 所有异常类型被统一吞掉，仅打印 traceback
- 无法区分可恢复错误（如 CUDA OOM）和不可恢复错误（如数据损坏）
- GPU 资源泄漏风险：CUDA 异常后可能没有正确释放锁

**重构方案**：
- 对已知异常类型（CUDA OOM、数值错误等）进行分类处理
- 添加错误状态标志，让主线程能感知 worker 线程的异常
- 确保在异常路径中正确释放 `_cuda_lock`

### 4.2 异常处理无状态反馈

**问题**：当 worker 线程发生异常时，主线程（`MainWindow._update_frames`）完全不知道，继续正常处理流程。用户无法感知系统内部错误。

**重构方案**：在 `ParallelPipeline` 中添加 `last_error` 属性和 `has_error` 标志，主线程可查询并显示错误。

---

## 5. 全局可变状态问题

### 5.1 直接修改模块级配置变量

**文件**: [gui/main_window.py:L452](../Software/Source_Code/gui/main_window.py#L452)

```python
config.STEREO_FOCAL_LENGTH_PX = avg_f
```

**问题**：直接修改 `config` 模块的模块级变量，这是一种隐式的全局状态变更。如果多个组件同时读取该值，可能导致不一致。

**重构方案**：引入配置管理器类，使用属性访问器确保线程安全：

```python
class Config:
    _instance = None
    _lock = threading.Lock()
    
    def __init__(self):
        self._stereo_focal_length_px = 609.157
    
    @property
    def stereo_focal_length_px(self):
        return self._stereo_focal_length_px
    
    def set_stereo_focal_length_px(self, value):
        with self._lock:
            self._stereo_focal_length_px = value
```

或者至少使用 `threading.Lock` 保护此变量的读写。

---

## 6. 工程化缺失

### 6.1 零单元测试

**现状**：约 15 个 Python 文件，约 2700+ 行代码，没有任何 `test_*.py` 文件。

**重构方案**：为核心模块添加基础单元测试：

- `tests/test_image_processor.py` — 测试裁剪、视差恢复、距离计算等纯函数
- `tests/test_config.py` — 测试配置值的合法性
- `tests/test_latency_tracker.py` — 测试延迟追踪器
- `tests/test_parallel_pipeline.py` — 测试并行流水线（需 mock 检测器）

使用 `pytest` 框架。

### 6.2 缺少构建/打包系统

**现状**：有 `requirements.txt` 但无 `setup.py`、`pyproject.toml`、`Makefile`。

**重构方案**：添加 `pyproject.toml`，定义项目元数据、依赖和脚本入口。

### 6.3 缺少代码格式化配置

**现状**：无 `.flake8`、`pyproject.toml [tool.ruff]`、`.editorconfig` 等代码风格配置。

**重构方案**：添加 `pyproject.toml` 中的 ruff 配置，确保代码风格一致。

---

## 7. 代码风格与可读性

### 7.1 过长的方法

`_update_frames` 方法（约 130 行）和 `_build_debug_visualization` 方法（约 65 行）过于冗长，内部逻辑分支多。

**重构方案**：将 `_update_frames` 拆分为：
- `_handle_preview_frame(frame)` — 处理预览状态帧
- `_handle_connected_frame(frame)` — 处理连接状态帧

### 7.2 魔术数字

多处使用未命名的魔术数字，如：
- `timer.setInterval(33)` — 应命名为 `FRAME_INTERVAL_MS`
- `max_iter=30` — 应使用配置常量
- `padding=k` 中的 `k = kernel_size // 2` — 可提炼为辅助函数

---

## 8. 潜在 Bug

### 8.1 视差恢复阈值与 FPGA 编码耦合

**文件**: [utils/image_processor.py:L234](../Software/Source_Code/utils/image_processor.py#L234)

```python
is_invalid = (r >= r_thresh) & (g <= g_thresh) & (b <= b_thresh)
```

**问题**：视差恢复中的有效/无效判定依赖硬编码的 RGB 阈值（默认 R>200, G<50, B<50），这些阈值与 FPGA 端的编码方式紧密耦合。如果编码格式变更，此处不会有任何警告。

**重构方案**：添加断言或文档说明这些阈值与 FPGA 端编码的对应关系，考虑添加版本号校验。

### 8.2 Calibration 中的计算重复

**文件**: [gui/main_window.py:L439-L456](../Software/Source_Code/gui/main_window.py#L439-L456)

`_on_calib_apply` 和 `_on_calib_add_sample` 中计算平均焦距的逻辑几乎完全相同，存在代码重复。

**重构方案**：提取公共方法 `_compute_average_focal()`。

---

## 9. 重构优先级

| 优先级 | 问题 | 影响范围 |
|---|---|---|
| **P0（必须）** | 状态管理改用 Enum | main_window.py 全局 |
| **P0（必须）** | 直接访问私有成员 → 添加公共 setter | main_window.py + parallel_pipeline.py |
| **P1（重要）** | 硬编码值引用 config | main_window.py, image_processor.py |
| **P1（重要）** | 添加类型注解 | 全部文件 |
| **P1（重要）** | 异常处理分类 + 错误状态反馈 | parallel_pipeline.py |
| **P2（建议）** | MainWindow 拆分为 Mixin 类 | main_window.py |
| **P2（建议）** | 添加单元测试 | 新建 tests/ |
| **P2（建议）** | 全局配置线程安全化 | config.py |
| **P3（可选）** | 添加 pyproject.toml | 项目根目录 |
| **P3（可选）** | 代码格式化配置 | 项目根目录 |

---

## 10. 重构执行顺序

1. **Phase 1**：Enum 状态管理 + 公共 setter 方法（P0，不改变外部行为）
2. **Phase 2**：硬编码值引用 config + 类型注解（P1）
3. **Phase 3**：异常处理改进 + 代码去重 + 方法拆分（P1-P2）
4. **Phase 4**：MainWindow 拆分 + 配置线程安全（P2）
5. **Phase 5**：单元测试 + 工程化配置（P2-P3）
