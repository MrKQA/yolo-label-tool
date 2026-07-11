# YOLO Label Tool

A YOLO image labeling, training, and video processing tool built with Flutter + Rust.

> Click to switch language / 点击切换语言

<details open>
<summary><b>English</b></summary>

## Overview

- **Frontend**: Flutter (Dart) — UI, annotation interaction, charts, video playback
- **Backend**: Rust — communicates with Flutter via Flutter Rust Bridge; training engine embeds Python through PyO3 to call Ultralytics
- **Video**: Rust integrates FFmpeg for frame extraction, metadata reading, and hardware decoding

## Current Features

- HBB / OBB / SEG annotation interface.
- AI-assisted annotation supports YOLO plus SAM3 text prompts and click prompts; SAM3 can output HBB / OBB / SEG annotations.
- Collaborative annotation over LAN with host approval and collaborator image-range assignment.
- `data.yaml` import, export, and Roboflow path compatibility.
- Training page: select `.pt` model, read dataset statistics, configure hyperparameters.
- Training engine uses PyO3 to call Python/Ultralytics for training.
- Training charts use `fl_chart` to display loss, mAP, precision, recall, LR.
- Resume training from `last.pt`: auto-detects `args.yaml` and `data.yaml`.
- Training history saved locally (up to 40 entries) with timestamps.
- Browse page includes Rust + FFmpeg video playback capabilities.
- Database table browsing supports project filtering, pagination, horizontal scrolling, row details, and a resizable detail panel.
- Read-only SQL queries are supported for inspection.

## Project Structure

```text
./
+-- Cargo.toml                    # Rust project config and dependencies
+-- flutter_rust_bridge.yaml      # Flutter Rust Bridge codegen config
+-- src/                          # Rust backend source
|   +-- api.rs                    # Public API exposed to Flutter
|   +-- training.rs               # Ultralytics training backend and Python process control
|   +-- detecting.rs              # YOLO / OpenVINO inference backend
|   +-- collaboration.rs          # LAN collaboration transport
|   +-- main.rs                   # Dev launcher entry
|   +-- frb_generated.rs          # Generated Flutter Rust Bridge glue
+-- flutter/                      # Flutter frontend
|   +-- pubspec.yaml              # Flutter dependencies and assets
|   +-- lib/
|       +-- main.dart             # App entry and global initialization
|       +-- app.dart              # Root app widget and top-level routing
|       +-- controllers/          # Workspace domain state controllers
|       +-- theme/                # Colors, dimensions, theme helpers
|       +-- services/             # Logger, i18n, config DB, Rust backend, import/export helpers
|       +-- models/               # Annotation, detection, training, shortcut, AI data models
|       +-- pages/                # Label, train, detect, crop, database, collaboration pages
|       |   +-- label/            # Label-page canvas, preview, toolbar, class widgets
|       +-- widgets/              # Reusable and page-specific widgets
|       |   +-- common/           # Navigation, overlays, workspace shell, floating messages
|       |   +-- database/         # Database browser sidebar, table, detail widgets
|       |   +-- detect/           # Detect panels, playback, prediction sequence widgets
|       |   +-- label/            # Label AI panel, grid painter, tool specs
|       |   +-- train/            # Training parameter, progress, resource and terminal widgets
|       +-- dialogs/              # Settings, export, shortcut, logs, SAM3 and training dialogs
|       +-- language/             # i18n JSON resources
|       +-- src/rust/             # Generated Dart bindings for Rust APIs
+-- models/                       # YOLO model files (git-ignored)
+-- datasets/                     # Export directory (configurable)
+-- ffmpeg/                       # FFmpeg binaries (download separately)
```

## Requirements

- Windows 10 / 11
- Rust toolchain
- Flutter SDK
- Visual Studio 2022 ("Desktop development with C++" workload)
- Python environment with `torch` and `ultralytics`; `onnxruntime` is optional for ONNX/GPU workflows, and SAM3 has extra optional dependencies below
- FFmpeg (for video frame extraction)

## Getting Started

### Launch

```bash
# Direct Flutter run
cd flutter
flutter pub get
flutter run -d windows

# Via Rust launcher
cargo run --package yolo_label_bridge --bin yolo_label_cli
```

### Generate FRB Code

After modifying `src/api.rs`:

```bash
flutter_rust_bridge_codegen generate
```

### Python Environment

Open the app → Settings → Preferences → Python Environment Path. Select `python.exe` or a Python environment folder. Green checkmark confirms detection.

#### YOLO / Training Environment

The training and YOLO AI annotation path uses [ultralytics/ultralytics](https://github.com/ultralytics/ultralytics). Install a PyTorch build that matches your GPU driver/CUDA from the [PyTorch previous versions](https://pytorch.org/get-started/previous-versions/) page, then install Ultralytics:

```bash
conda create -n yolo python=3.12
conda activate yolo
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
pip install ultralytics opencv-python
```

`onnxruntime-gpu` is only needed when using ONNX/GPU inference. If the app logs an ONNX import warning but you only train with `.pt` models, it can be ignored.

#### OpenVINO Inference on Intel Devices

The Browse page can use [Ultralytics OpenVINO](https://docs.ultralytics.com/integrations/openvino/) exports for inference on Intel hardware. Export the model first. If the exported `*_openvino_model/` directory is next to the original `.pt`, you can keep selecting the `.pt` model and the app will auto-use the export for Intel inference; selecting the generated `.xml` also works:

```bash
python -c "from ultralytics import YOLO; YOLO('yolo26n.pt').export(format='openvino')"
python -c "from openvino import Core; print(Core().available_devices)"
```

Automatic inference priority is NVIDIA CUDA, then Intel GPU, NPU, CPU through OpenVINO, then CPU fallback. iGPU, NPU, and CPU are inference-only here; YOLO training still uses NVIDIA CUDA or CPU. If Intel devices are not detected, update OpenVINO and Intel drivers.

The Training page has Export Settings for ONNX and OpenVINO. `data.yaml` is only used for INT8 calibration; when auto-export after training is enabled, the current training dataset `data.yaml` is used automatically.

#### SAM3 Assisted Annotation Environment

SAM3 assisted annotation is only used on the Label page. It supports text prompt segmentation and click prompt refinement: left click adds positive target points, right click adds negative/exclusion points. Output mode can be HBB, OBB, or SEG.

Install [facebookresearch/sam3](https://github.com/facebookresearch/sam3) in the Python environment selected in Settings, or use a separate SAM3 environment and select its `python.exe`:

```bash
conda create -n sam3 python=3.12
conda activate sam3
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
git clone https://github.com/facebookresearch/sam3.git
cd sam3
pip install -e .
pip install opencv-python matplotlib pandas tqdm psutil
```

Notes:

- Official SAM3 currently expects Python 3.12+, PyTorch 2.7+, and a CUDA-capable GPU.
- On native Windows, install `triton-windows` if the log reports `No module named 'triton'`: `pip install triton-windows`.
- `opencv-python` is recommended because the app converts SAM3 masks into SEG polygon contours. `matplotlib`, `pandas`, `tqdm`, and `psutil` are commonly required by the SAM3 runtime and examples. Without OpenCV, a slower numpy fallback is used.
- For 6-8 GB laptop GPUs, use the SAM3 Config panel with low-memory settings such as `precision=fp16`, `encoder=vit_b`, batch size `1`, and pre-resize `1024x768` or lower. `vit_l` and `vit_h` can be selected for matching checkpoints, but they need more VRAM and are not recommended as the default on low-memory GPUs.
- `torch.compile` can be enabled in the SAM3 Config panel. It is feasible on PyTorch 2.7+ only when the SAM3 model can reuse the compiled graph after a slow warm-up call. Because this app currently runs SAM3 through per-request Python processes, enabling compile may pay the warm-up cost every time. On native Windows it can also fail or compile slowly because it depends on the PyTorch/Triton stack.
- Download or prepare the SAM3 checkpoint according to the SAM3 repository instructions, then select the `.pt` file in the AI → SAM3 panel. The selected path is saved for later launches.

### Training

1. Configure Python environment and output path in Settings
2. Training page: select `.pt` model → select `data.yaml` dataset
3. Adjust hyperparameters → click "Start Training"
4. Click "Stop" during training; "Continue Training" to resume
5. Real-time charts for loss, mAP, precision, etc.

### Video Frame Extraction

1. Switch to the "Crop" page
2. Import video files (mp4, avi, mov, mkv, etc.)
3. Set frame interval, output format, quality
4. Click "Start Extraction", choose output directory

### Annotation Export

Label page → right toolbar → Export button → configure options → exports YOLO directory structure.

### Collaborative Annotation

1. Host opens images and starts host mode on the Collaboration page.
2. Collaborators discover the host on LAN and request to join.
3. Host approves collaborators and assigns image index ranges.
4. Collaborators annotate assigned images; classes, colors, authors, and boxes sync through the host.

### Database Management

The left sidebar contains a database management page for inspecting `AnnotationConfig.db`.

1. Select a table from the collapsible table browser.
2. Use the Browse tab to view rows. The project selector is below the Browse tab.
3. Use the bottom bar to change row count (`50 / 100 / 200`) and switch pages.
4. Drag the divider between the table and the detail panel to resize the detail area.
5. Use the Structure tab to inspect table fields.
6. Use the SQL tab for read-only `SELECT` / `WITH` queries and schema `PRAGMA` queries.

## FFmpeg Setup

Video frame extraction requires FFmpeg. Use [gyan.dev](https://www.gyan.dev/ffmpeg/) Windows builds.

### Download

1. Open https://www.gyan.dev/ffmpeg/builds/packages/
2. Download **ffmpeg-release-full.7z** (full build)
3. Extract to project root under `ffmpeg/`

### Search Order

```text
1. Environment variable FFMPEG_PATH
2. Project root/ffmpeg/bin/ffmpeg.exe    ← recommended
3. System PATH
```

Place the extracted files as:

```text
ffmpeg/
└── bin/
    ├── ffmpeg.exe
    ├── ffprobe.exe
    └── ...
```

### Notes

- Must use the **full** build — essential build lacks codecs.
- `ffmpeg/` is git-ignored.
- Hardware decoder auto-detect: NVIDIA CUDA → Intel QSV → D3D11VA → CPU.
- If extraction fails, verify `ffmpeg/bin/ffmpeg.exe` exists or set `FFMPEG_PATH`.

## Config Database

Runtime configuration is stored in `AnnotationConfig.db` in the program root.
The database contains settings, recent files/folders, keybindings, training
preferences, training history, application logs, image records, classes, and
annotations. Legacy JSON config files and the old database name are no longer
read by the application.

The built-in database page is intended for inspection and troubleshooting. SQL
execution is limited to read-only queries to avoid accidentally modifying
annotation data.

## FAQ

### Rust compilation fails

Verify Rust: `rustc --version`. PyO3 errors: `conda activate yolo && cargo check`.

### Training fails immediately

Check Python green checkmark, `ultralytics` installed, `data.yaml` path valid, device exists.

### Stop not immediate

Safe interruption via Ultralytics callbacks at batch/epoch boundaries — short delay expected.

### Page state lost after tab switch

All pages kept alive via `IndexedStack` — training, playback, crop state preserved.

</details>

<details>
<summary><b>简体中文</b></summary>

## 概述

- **前端**：Flutter（Dart），负责界面、标注交互、图表、视频播放
- **后端**：Rust，通过 Flutter Rust Bridge 与前端通信；训练引擎通过 PyO3 嵌入 Python 调用 Ultralytics
- **视频**：Rust 端集成 FFmpeg 实现视频取帧、元数据读取、硬件解码

## 当前能力

- HBB / OBB / SEG 标注界面。
- AI 辅助标注支持 YOLO，以及 SAM3 文本提示词和点击提示；SAM3 可输出 HBB / OBB / SEG 标注。
- 局域网协助标注：主机确认加入，并为协助者分配图片索引范围。
- `data.yaml` 导入、导出和 Roboflow 路径兼容。
- 训练页支持选择 `.pt` 模型、读取数据集统计、设置超参数。
- 训练引擎使用 PyO3 调用 Python / Ultralytics 执行训练。
- 训练曲线使用 `fl_chart` 显示 loss、mAP、precision、recall、LR 等指标。
- 支持从 `last.pt` 读取训练目录和 `args.yaml`，自动匹配 `data.yaml` 并启用 resume。
- 最近训练记录保存到本地配置，最多保留 40 条，并显示明确时间点。
- 浏览页包含 Rust + FFmpeg 视频处理能力。
- 数据库表浏览支持项目筛选、分页、横向滚动、行详情和可拖拽伸缩的详情区域。
- SQL 查看支持只读查询。

## 项目结构

```text
./
+-- Cargo.toml                    # Rust 项目配置与依赖
+-- flutter_rust_bridge.yaml      # Flutter Rust Bridge 代码生成配置
+-- src/                          # Rust 后端源码
|   +-- api.rs                    # 暴露给 Flutter 的公共 API
|   +-- training.rs               # Ultralytics 训练后端与 Python 子进程控制
|   +-- detecting.rs              # YOLO / OpenVINO 推理后端
|   +-- collaboration.rs          # 局域网协助标注通信
|   +-- main.rs                   # 开发启动入口
|   +-- frb_generated.rs          # Flutter Rust Bridge 生成代码
+-- flutter/                      # Flutter 前端
|   +-- pubspec.yaml              # Flutter 依赖与资源配置
|   +-- lib/
|       +-- main.dart             # 应用入口与全局初始化
|       +-- app.dart              # 根 Widget 与顶层路由
|       +-- controllers/          # 工作区领域状态控制器
|       +-- theme/                # 颜色、尺寸、主题辅助函数
|       +-- services/             # 日志、语言、配置数据库、Rust 后端、导入导出辅助
|       +-- models/               # 标注、检测、训练、快捷键、AI 数据模型
|       +-- pages/                # 标注、训练、检测、裁剪、数据库、协助页面
|       |   +-- label/            # 标注页画布、预览、工具栏、类别组件
|       +-- widgets/              # 通用组件和页面专属组件
|       |   +-- common/           # 导航、遮罩、工作区壳、浮动消息
|       |   +-- database/         # 数据库侧栏、表格、详情组件
|       |   +-- detect/           # 检测参数、播放、预测序列组件
|       |   +-- label/            # 标注 AI 面板、网格绘制、工具定义
|       |   +-- train/            # 训练参数、进度、资源占用、终端组件
|       +-- dialogs/              # 设置、导出、快捷键、日志、SAM3、训练相关弹窗
|       +-- language/             # 多语言 JSON 资源
|       +-- src/rust/             # Rust API 生成的 Dart 绑定
+-- models/                       # YOLO 模型文件目录（不提交到 Git）
+-- datasets/                     # 标注导出目录（可配置）
+-- ffmpeg/                       # FFmpeg 二进制文件（需自行下载）
```

## 环境要求

- Windows 10 / 11
- Rust 工具链
- Flutter SDK
- Visual Studio 2022（"使用 C++ 的桌面开发" 工作负载）
- Python 环境（需安装 `torch`、`ultralytics`；`onnxruntime` 仅在 ONNX/GPU 流程中需要，SAM3 额外依赖见下方）
- FFmpeg（视频取帧依赖）

## 使用方法

### 启动

```bash
# 直接启动 Flutter
cd flutter
flutter pub get
flutter run -d windows

# 通过 Rust 启动器
cargo run --package yolo_label_bridge --bin yolo_label_cli
```

### 生成桥接代码

修改 `src/api.rs` 后：

```bash
flutter_rust_bridge_codegen generate
```

### Python 环境

打开软件 → 设置 → 首选项 → Python 环境路径，选择 `python.exe` 或环境文件夹。绿色勾表示可用。

#### YOLO / 训练环境

训练和 YOLO AI 辅助标注使用 [ultralytics/ultralytics](https://github.com/ultralytics/ultralytics)。先从 [PyTorch previous versions](https://pytorch.org/get-started/previous-versions/) 选择与显卡驱动 / CUDA 匹配的 PyTorch，再安装 Ultralytics：

```bash
conda create -n yolo python=3.12
conda activate yolo
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
git clone https://github.com/ultralytics/ultralytics.git
cd ultralytics
pip install -e . opencv-python
```

`onnxruntime-gpu` 只在 ONNX/GPU 推理时需要。如果只使用 `.pt` 模型训练，日志中出现 ONNX 导入警告可以忽略。

#### Intel 设备 OpenVINO 推理

浏览页面可以使用 [Ultralytics OpenVINO](https://docs.ultralytics.com/zh/integrations/openvino/) 导出模型在 Intel 硬件上推理。请先导出 OpenVINO 模型；如果生成的 `*_openvino_model/` 目录与原 `.pt` 在同一目录，可以继续选择原 `.pt`，软件会在 Intel 推理时自动使用导出目录；直接选择生成目录内的 `.xml` 也可以：

```bash
python -c "from ultralytics import YOLO; YOLO('yolo26n.pt').export(format='openvino')"
python -c "from openvino import Core; print(Core().available_devices)"
```

自动推理优先级为 NVIDIA CUDA，其次是 OpenVINO 的 Intel GPU、NPU、CPU，最后回退 CPU。iGPU、NPU、CPU 在本工具中只用于推理；YOLO 训练仍使用 NVIDIA CUDA 或 CPU。如果 Intel 设备无法识别，请更新 OpenVINO 和 Intel 驱动。

训练页提供 ONNX 和 OpenVINO 的导出设置。`data.yaml` 仅用于 INT8 量化校准；勾选训练完成后自动导出时，会自动使用本次训练的数据集 `data.yaml`。

#### SAM3 辅助标注环境

SAM3 只用于标注页面的 AI 辅助标注，支持文本提示词分割和点击提示微调：左键添加目标正点，右键添加排除负点。输出模式可选择 HBB、OBB 或 SEG。

在设置中选择的 Python 环境内安装 [facebookresearch/sam3](https://github.com/facebookresearch/sam3)，也可以单独创建 SAM3 环境并选择该环境的 `python.exe`：

```bash
conda create -n sam3 python=3.12
conda activate sam3
pip install torch torchvision --index-url https://download.pytorch.org/whl/cu128
git clone https://github.com/facebookresearch/sam3.git
cd sam3
pip install -e .
pip install opencv-python matplotlib pandas tqdm psutil
```

注意事项：

- SAM3 官方当前要求 Python 3.12+、PyTorch 2.7+，并需要支持 CUDA 的显卡。
- Windows 原生环境如果日志出现 `No module named 'triton'`，安装 `triton-windows`：`pip install triton-windows`。
- 推荐安装 `opencv-python`，软件会用它把 SAM3 mask 转成 SEG 多边形轮廓；`matplotlib`、`pandas`、`tqdm`、`psutil` 也是 SAM3 运行和示例中常用依赖。没有 OpenCV 时会使用较慢的 numpy fallback。
- 6-8 GB 显存的笔记本显卡建议在 SAM3 配置面板使用低显存参数：`precision=fp16`、`encoder=vit_b`、batch size `1`，预缩放 `1024x768` 或更低。`vit_l` 和 `vit_h` 可用于匹配的 checkpoint，但需要更多显存，不建议作为低显存默认选项。
- `torch.compile` 可在 SAM3 配置面板开启。它在 PyTorch 2.7+ 上只有在 SAM3 模型复用编译图时才适合加速重复推理；当前工具的 SAM3 仍是按请求启动 Python 子进程，开启后可能每次都承担预热成本。Windows 原生环境还可能受 PyTorch/Triton 编译链影响而失败或耗时较长。
- 按 SAM3 仓库说明下载或准备 checkpoint 后，在 AI → SAM3 面板选择 `.pt` 文件；路径会被保存，后续启动无需重复选择。

### 训练

1. 设置中配置 Python 环境和训练输出路径
2. 训练页选择 `.pt` 模型 → 选择 `data.yaml` 数据集
3. 调整超参数 → 点击"开始训练"
4. 训练中可点击"停止"，后续可"继续训练"
5. 训练曲线实时显示 loss、mAP、precision 等指标

### 视频取帧

1. 切换到"裁剪"页面
2. 导入视频文件（支持 mp4、avi、mov、mkv 等）
3. 设置取帧间隔、输出格式、画质参数
4. 点击"开始提取"，选择输出目录

### 标注导出

标注页右侧工具栏 → 导出按钮 → 配置选项 → 导出 YOLO 目录结构。

### 协助标注

1. 主机打开图片后，在协作页面开启主机。
2. 协助者在局域网内发现主机并申请加入。
3. 主机确认协助者，并分配图片索引范围。
4. 协助者标注分配范围内的图片，类别、颜色、作者和标注框通过主机同步。

### 数据库管理

左侧侧边栏中包含数据库管理页面，用于查看 `AnnotationConfig.db`。

1. 在可伸缩的数据表列表中选择要查看的表。
2. 在"浏览"选项卡中查看数据，项目下拉框位于"浏览"选项卡下方。
3. 底部可选择每页行数（`50 / 100 / 200`）并切换页码。
4. 表格和右侧详情之间的分隔条可用鼠标左右拖拽，调整详情区域宽度。
5. "结构"选项卡用于查看表字段。
6. "SQL"选项卡仅允许只读 `SELECT` / `WITH` 查询和查看结构的 `PRAGMA` 查询。

## FFmpeg 配置

视频取帧功能依赖 FFmpeg。推荐使用 [gyan.dev](https://www.gyan.dev/ffmpeg/) 的 Windows 构建版本。

### 下载

1. 打开 https://www.gyan.dev/ffmpeg/builds/packages/
2. 下载 **ffmpeg-release-full.7z**（full 版本）
3. 解压到项目根目录下的 `ffmpeg/` 文件夹

### 查找顺序

```text
1. 环境变量 FFMPEG_PATH
2. 项目目录/ffmpeg/bin/ffmpeg.exe    ← 推荐
3. 系统 PATH 中的 ffmpeg
```

目录放置：

```text
ffmpeg/
└── bin/
    ├── ffmpeg.exe
    ├── ffprobe.exe
    └── ...
```

### 注意事项

- **必须下载 full 版本**，essential 版本缺少部分编解码器。
- `ffmpeg/` 目录已在 `.gitignore` 中排除，不会提交到 Git。
- 硬件解码器自动检测（优先 NVIDIA CUDA → Intel QSV → D3D11VA → CPU）。
- 取帧失败时检查 `ffmpeg/bin/ffmpeg.exe` 是否存在，或设置 `FFMPEG_PATH`。

## 配置数据库

程序根目录会自动创建 `AnnotationConfig.db`，用于保存设置、最近文件/文件夹、
自定义按键、训练参数偏好、训练历史、应用日志、图片记录、类别和标注信息。
程序不再读取旧 JSON 配置文件，也不再兼容旧数据库文件名。

内置数据库页面主要用于查看和排查问题。SQL 执行被限制为只读查询，避免误修改
标注数据或配置数据。

## 常见问题

### Rust 编译失败

确认 Rust：`rustc --version`。PyO3 链接错误：`conda activate yolo && cargo check`。

### 训练启动后立刻失败

检查 Python 绿色勾、`ultralytics` 已安装、`data.yaml` 路径正确、device 存在。

### 停止不立即生效

通过 Ultralytics callback 安全中断，在 batch/epoch 回调时生效，短暂延迟正常。

### 页面切换后状态丢失

使用 `IndexedStack` 保持所有页面存活，切换时保留训练进度、播放和裁剪状态。

</details>
