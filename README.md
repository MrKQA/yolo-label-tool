# YOLO Label Tool

基于 Flutter + Rust 的 YOLO 标注、训练和视频处理工具。前端使用 Flutter，后端通过 Flutter Rust Bridge 调用 Rust；训练模块通过 PyO3 嵌入 Python，并调用 Ultralytics YOLO。

## 当前能力

- HBB / OBB / SEG 标注界面。
- `data.yaml` 导入、导出和 Roboflow 路径兼容。
- 训练页支持选择 `.pt` 模型、读取数据集统计、设置超参数。
- 训练页使用 PyO3 调用 Python / Ultralytics 执行训练。
- 训练曲线使用 `fl_chart` 显示 loss、mAP、precision、recall、lr 等指标。
- 支持从 `last.pt` 读取训练目录和 `args.yaml`，自动匹配 `data.yaml` 并启用 resume。
- 最近训练记录保存到本地配置，最多保留 40 条，并显示明确时间点。
- 浏览页包含 Rust + FFmpeg 视频处理能力。

## 项目结构

```text
.
├── Cargo.toml
├── flutter_rust_bridge.yaml
├── src/
│   ├── api.rs              # Rust 暴露给 Flutter 的接口
│   ├── training.rs         # PyO3 + Ultralytics 训练后端
│   ├── main.rs             # 开发启动器，构建 Rust 并启动 Flutter GUI
│   └── frb_generated.rs
├── flutter/
│   ├── pubspec.yaml
│   └── lib/
│       ├── main.dart
│       ├── LabelPage.dart
│       ├── TrainPage.dart
│       ├── DetectVideoPage.dart
│       ├── SettingsDialog.dart
│       ├── ConfigStore.dart
│       └── language/
└── README.md
```

## 环境要求

- Windows 10 / Windows 11。
- Rust 工具链。
- Flutter SDK。
- Visual Studio C++ 桌面开发工具链。
- Python 环境，需要安装：

```bash
pip install ultralytics torch onnxruntime
```

如果需要 CUDA 训练，请根据你的显卡和 CUDA 版本安装对应的 PyTorch CUDA 版本。

## 运行

### 直接启动 Flutter

```bash
cd flutter
flutter pub get
flutter run -d windows
```

### 使用 Rust 启动器

在项目根目录执行：

```bash
cargo run --package yolo_label_bridge --bin yolo_label_cli
```

这个启动器会先构建 Rust，再启动 Flutter Windows GUI。

## 生成 Flutter Rust Bridge 代码

修改 `src/api.rs` 或暴露给 Flutter 的 Rust 类型后，需要重新生成绑定：

```bash
flutter_rust_bridge_codegen generate
```

生成内容主要位于：

```text
flutter/lib/src/rust/
src/frb_generated.rs
```

## Python 环境配置

打开软件后进入：

```text
设置 -> 首选项 -> Python 环境路径
```

可以选择：

- Python 环境文件夹。
- `python.exe`。

软件会尝试自动识别环境，并运行以下检查：

```python
import torch
import onnxruntime
print(torch.__version__)
print(torch.cuda.is_available())
print(torch.cuda.device_count())
print(torch.cuda.get_device_name(0))
print(onnxruntime.get_device())
```

识别成功后，路径按钮旁会显示绿色勾。

## PyO3 训练注意事项

训练后端现在通过 PyO3 嵌入 Python，而不是启动独立的 Python 子进程。

需要注意：

- PyO3 会绑定当前 Rust 构建时可找到的 Python 主版本。
- 设置页中选择的 Python 环境最好和 Rust 构建绑定的 Python 主版本一致。
- 如果 Python 主版本或 ABI 不一致，`torch`、`onnxruntime` 这类 native 包可能导入失败。
- Windows 下建议使用完整路径选择 `python.exe`，例如：

```text
D:\miniconda3\envs\yolo\python.exe
```

- 如果你使用 Conda 环境，建议先在命令行确认：

```bash
python -c "import torch, onnxruntime; print(torch.__version__); print(torch.cuda.is_available()); print(onnxruntime.get_device())"
```

## 训练用法

1. 在设置中配置 Python 环境路径。
2. 设置训练结果保存位置。
3. 在训练页点击“选择 PT 模型”。
4. 点击“选择数据集”，选择 YOLO 数据集的 `data.yaml`。
5. 检查 train / val / test 数量和 classes 是否正确。
6. 调整 `epochs`、`imgsz`、`batch`、`device`、`amp`、`cls_pw` 等参数。
7. 点击“开始训练”。

训练过程中：

- 按钮会变成“停止”。
- 点击“停止”会请求训练安全中断。
- 停止后可以再次点击“继续训练”。
- 训练曲线会按 epoch 更新。
- 最近训练记录会保留最近 40 次开始、继续、停止操作。

### 恢复中断训练

选择训练结果目录中的：

```text
weights/last.pt
```

软件会尝试读取同一训练目录下的：

```text
args.yaml
results.csv
```

如果判断该训练未完成，并且能匹配数据集路径：

- 自动选择对应 `data.yaml`。
- 默认开启 resume。
- 按钮文字显示为“继续训练”。

## 训练图表

训练页图表使用 `fl_chart` 实现，当前显示：

- Train Loss
- Val Loss
- mAP@0.5
- mAP@0.5:0.95
- Precision
- Recall
- LR

图表按 epoch 追加数据点，右侧显示当前最新指标值。

## 配置文件

配置文件保存在当前 Windows 用户目录下：

```text
%USERPROFILE%\.rustlabel\
```

主要文件：

```text
history.json           # 最近打开的文件和文件夹
keybindings.json       # 自定义快捷键
settings.json          # Python 路径、训练结果路径、导出路径
training_history.json  # 最近 40 次训练操作记录
```

## 常见问题

### 构建时报找不到 Python 或 PyO3 链接失败

确认命令行能找到 Python：

```bash
python --version
```

如果使用 Conda，建议先激活环境后再构建：

```bash
conda activate yolo
cargo check
```

### 训练启动后立刻失败

优先检查：

- 设置页 Python 环境是否显示绿色勾。
- 是否安装 `ultralytics`。
- `data.yaml` 路径是否正确。
- `torch.cuda.is_available()` 是否符合预期。
- 选择的 `device` 是否存在。

### 点击停止不是立即退出

当前停止逻辑通过 Ultralytics callback 检查停止标记文件。它会在 batch 或 epoch 回调时安全中断，因此不是硬杀进程，可能会有短暂延迟。

## 依赖概览

Rust：

- `flutter_rust_bridge`
- `once_cell`
- `pyo3`

Flutter：

- `flutter_rust_bridge`
- `file_selector`
- `flex_color_picker`
- `fl_chart`
- `video_player`
- `video_player_win`
