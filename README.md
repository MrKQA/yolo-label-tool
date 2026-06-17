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
├── Cargo.toml                  # Rust project config & dependencies
├── flutter_rust_bridge.yaml    # FRB codegen config
├── src/                        # Rust source
│   ├── api.rs                  # Public API exposed to Flutter
│   ├── training.rs             # PyO3 + Ultralytics training backend
│   ├── detecting.rs            # PyO3 + Ultralytics YOLO inference
│   ├── main.rs                 # Dev launcher
│   └── frb_generated.rs        # FRB auto-generated glue code
├── flutter/                    # Flutter frontend
│   ├── pubspec.yaml
│   └── lib/
│       ├── main.dart           # App entry, global state, page routing
│       ├── LabelPage.dart      # Annotation page
│       ├── TrainPage.dart      # Training page
│       ├── DetectVideoPage.dart # Browse / video playback page
│       ├── CropPage.dart       # Video frame extraction page
│       ├── DatabasePage.dart   # SQLite database browser / management page
│       ├── ExportDialog.dart   # Annotation export dialog
│       ├── ConfigStore.dart    # Config persistence
│       ├── SettingsDialog.dart # Settings dialog
│       ├── AnnotationModels.dart
│       ├── ShortcutModels.dart
│       ├── FloatingMessage.dart
│       ├── RustVideoBackend.dart
│       └── language/           # i18n resources
├── models/                     # YOLO model files (git-ignored)
├── datasets/                   # Export directory (configurable)
└── ffmpeg/                     # FFmpeg binaries (download separately)
```

## Requirements

- Windows 10 / 11
- Rust toolchain
- Flutter SDK
- Visual Studio 2022 ("Desktop development with C++" workload)
- Python environment with `ultralytics`, `torch`, `onnxruntime`
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
├── Cargo.toml                  # Rust 项目配置与依赖
├── flutter_rust_bridge.yaml    # FRB 代码生成配置
├── src/                        # Rust 源码
│   ├── api.rs                  # 对 Flutter 暴露的接口
│   ├── training.rs             # PyO3 + Ultralytics 训练后端
│   ├── detecting.rs            # PyO3 + Ultralytics YOLO 推理
│   ├── main.rs                 # 开发启动器
│   └── frb_generated.rs        # FRB 自动生成的胶水代码
├── flutter/                    # Flutter 前端
│   ├── pubspec.yaml
│   └── lib/
│       ├── main.dart           # 应用入口、全局状态、页面路由
│       ├── LabelPage.dart      # 标注页
│       ├── TrainPage.dart      # 训练页
│       ├── DetectVideoPage.dart # 浏览/视频播放页
│       ├── CropPage.dart       # 视频取帧裁剪页
│       ├── DatabasePage.dart   # SQLite 数据库查看/管理页
│       ├── ExportDialog.dart   # 标注导出弹窗
│       ├── ConfigStore.dart    # 配置持久化
│       ├── SettingsDialog.dart # 设置弹窗
│       ├── AnnotationModels.dart
│       ├── ShortcutModels.dart
│       ├── FloatingMessage.dart
│       ├── RustVideoBackend.dart
│       └── language/           # 多语言资源
├── models/                     # YOLO 模型文件（不提交到 Git）
├── datasets/                   # 标注导出目录（可配置）
└── ffmpeg/                     # FFmpeg 二进制（需自行下载）
```

## 环境要求

- Windows 10 / 11
- Rust 工具链
- Flutter SDK
- Visual Studio 2022（"使用 C++ 的桌面开发" 工作负载）
- Python 环境（需安装 `ultralytics`、`torch`、`onnxruntime`）
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
