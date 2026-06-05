# YOLO Label Tool

基于 Flutter + Rust 的 YOLO 图像标注、训练和视频处理工具。

- **前端**：Flutter（Dart），负责界面、标注交互、图表、视频播放
- **后端**：Rust，通过 Flutter Rust Bridge 与前端通信；训练引擎通过 PyO3 嵌入 Python 调用 Ultralytics
- **视频**：Rust 端集成 FFmpeg 实现视频取帧、元数据读取、硬件解码

## 项目结构

```text
├── Cargo.toml                  # Rust 项目配置与依赖
├── flutter_rust_bridge.yaml    # FRB 代码生成配置
├── src/                        # Rust 源码
│   ├── api.rs                  # 对 Flutter 暴露的接口（标注、视频、训练、裁剪）
│   ├── training.rs             # PyO3 + Ultralytics 训练后端
│   ├── main.rs                 # 开发启动器（构建 Rust 并启动 Flutter GUI）
│   └── frb_generated.rs        # FRB 自动生成的胶水代码
├── flutter/                    # Flutter 前端
│   ├── pubspec.yaml            # Dart 依赖配置
│   └── lib/
│       ├── main.dart           # 应用入口、全局状态、页面路由
│       ├── LabelPage.dart      # 标注页（画布、绘制、交互）
│       ├── TrainPage.dart      # 训练页（模型选择、超参数、图表）
│       ├── DetectVideoPage.dart # 浏览/视频播放页
│       ├── CropPage.dart       # 视频取帧裁剪页
│       ├── ExportDialog.dart   # 标注导出弹窗
│       ├── ConfigStore.dart    # 配置持久化（JSON 读写）
│       ├── SettingsDialog.dart # 设置弹窗
│       ├── AnnotationModels.dart # 标注数据模型（HBB/OBB/SEG）
│       ├── ShortcutModels.dart  # 快捷键模型
│       ├── FloatingMessage.dart # 浮动提示组件
│       ├── RustVideoBackend.dart # Rust FFI 视频后端封装
│       └── language/           # 多语言资源
├── models/                     # YOLO 模型文件（.pt，不提交到 Git）
├── datasets/                   # 标注导出目录（可配置）
└── ffmpeg/                     # FFmpeg 二进制（需自行下载）
```

## 环境要求

- Windows 10 / 11
- Rust 工具链
- Flutter SDK
- Visual Studio 2022（"使用 C++ 的桌面开发" 工作负载）
- Python 环境（需安装 `ultralytics`、`torch`、`onnxruntime`）
- FFmpeg（用于视频取帧，见下方说明）

## 使用方法

### 启动

```bash
# 方式一：直接启动 Flutter
cd flutter
flutter pub get
flutter run -d windows

# 方式二：通过 Rust 启动器
cargo run --package yolo_label_bridge --bin yolo_label_cli
```

### 生成 Flutter Rust Bridge 代码

修改 `src/api.rs` 后需要重新生成绑定：

```bash
flutter_rust_bridge_codegen generate
```

### Python 环境

打开软件 → 设置 → 首选项 → Python 环境路径，选择 `python.exe` 或环境文件夹。软件会自动检测 Python 环境并显示绿色勾确认可用。

### 训练

1. 设置中配置 Python 环境和训练输出路径
2. 训练页选择 `.pt` 模型 → 选择 `data.yaml` 数据集
3. 调整超参数 → 点击"开始训练"
4. 训练过程中可点击"停止"，后续可"继续训练"
5. 训练曲线实时显示 loss、mAP、precision 等指标

### 视频取帧（裁剪页）

1. 切换到"裁剪"页面
2. 导入视频文件（支持 mp4、avi、mov、mkv 等）
3. 设置取帧间隔、输出格式、画质参数
4. 点击"开始提取"，选择输出目录

### 标注导出

标注页右侧工具栏 → 导出按钮 → 配置是否跳过空标注、是否导出图片、train/val/test 比例 → 导出 YOLO 目录结构。

## FFmpeg 配置

视频取帧功能依赖 FFmpeg。推荐使用 [gyan.dev](https://www.gyan.dev/ffmpeg/builds/packages/) 的 Windows 构建版本。

### 下载

1. 打开 https://www.gyan.dev/ffmpeg/builds/packages/
2. 下载 **ffmpeg-release-full.7z**（推荐 full 版本，编解码器最全）
3. 解压到项目根目录下的 `ffmpeg/` 文件夹

### 目录结构

项目运行时按以下顺序查找 FFmpeg：

```text
1. 环境变量 FFMPEG_PATH 指向的路径
2. 项目目录/ffmpeg/bin/ffmpeg.exe    ← 推荐此方式
3. 系统 PATH 中的 ffmpeg
```

推荐将解压后的 `bin/` 目录放到项目 `ffmpeg/` 下：

```text
ffmpeg/
└── bin/
    ├── ffmpeg.exe
    ├── ffprobe.exe
    └── ...
```

### 注意事项

- **必须下载 full 版本**，essential 版本缺少部分编解码器，可能导致某些视频格式无法处理。
- `ffmpeg/` 目录已在 `.gitignore` 中排除，不会提交到 Git。
- 硬件解码器会自动检测（优先 NVIDIA CUDA → Intel QSV → D3D11VA → CPU），无需额外配置。
- 如果视频取帧失败，检查 `ffmpeg/bin/ffmpeg.exe` 是否存在，或设置环境变量 `FFMPEG_PATH` 指向 ffmpeg.exe 所在目录。

## 配置文件

配置保存在 `%USERPROFILE%\.rustlabel\`：

| 文件 | 内容 |
|------|------|
| `settings.json` | Python 路径、训练输出路径、导出路径 |
| `history.json` | 最近打开的文件和文件夹 |
| `keybindings.json` | 自定义快捷键 |
| `training_preferences.json` | 训练参数偏好（模型、超参数、图表颜色） |
| `training_history.json` | 最近训练操作记录 |

## 常见问题

### Rust 编译失败

确认 Rust 工具链已安装：`rustc --version`。如果 PyO3 链接错误，先激活 Python 环境再编译：`conda activate yolo && cargo check`。

### 训练启动后立刻失败

检查设置页 Python 环境是否显示绿色勾、是否安装了 `ultralytics`、`data.yaml` 路径是否正确、`device` 参数中的 GPU 是否存在。

### 点击停止不会立刻终止

停止逻辑通过 Ultralytics callback 安全中断，在 batch 或 epoch 回调时生效，可能有短暂延迟。

### 页面切换后状态丢失

已使用 `IndexedStack` 保持所有页面存活，切换页面不会丢失训练进度、视频播放或裁剪状态。
