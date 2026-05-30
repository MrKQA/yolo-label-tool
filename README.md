# YOLO Label Tool

基于 Flutter + Rust 的 YOLO 图像标注与训练工具，使用 Flutter Rust Bridge 实现前后端桥接。

## 版本信息

| 组件 | 版本 |
|------|------|
| Rust | 1.95.0 (2026-04-14) |
| Flutter | 3.44.0 (stable) |
| Dart | 3.12.0 |
| DevTools | 2.57.0 |

## 依赖库

### Rust 侧 ([Cargo.toml](Cargo.toml))

| 库 | 版本 | 用途 |
|----|------|------|
| flutter_rust_bridge | 2.11.1 | Flutter 与 Rust 双向 FFI 桥接 |

Crate 类型：`cdylib` + `staticlib` + `rlib`

### Flutter 侧 ([pubspec.yaml](flutter/pubspec.yaml))

| 库 | 版本 | 用途 |
|----|------|------|
| flutter | SDK | Flutter 框架 |
| flutter_rust_bridge | 2.11.1 | Rust 桥接 Dart 端 |
| file_selector | ^1.0.4 | 文件/文件夹选择对话框 |
| flex_color_picker | ^3.8.0 | 色板、色轮和颜色代码选择器 |

## 项目结构

```
├── Cargo.toml                  # Rust 项目配置
├── flutter_rust_bridge.yaml    # FRB 代码生成配置
├── src/
│   ├── main.rs                 # Rust 启动器（构建并启动 Flutter Windows GUI）
│   ├── lib.rs                  # Rust 库入口
│   ├── api.rs                  # FRB 暴露给 Flutter 的 API
│   └── frb_generated.rs        # FRB 自动生成代码
├── flutter/
│   ├── pubspec.yaml            # Flutter 项目配置
│   └── lib/
│       ├── main.dart           # 应用壳层、全局状态与页面切换
│       ├── LabelPage.dart      # 标注页面（画布、绘制、交互）
│       ├── TrainPage.dart      # 训练页面
│       ├── DetectVideoPage.dart # 视频检测/浏览页面
│       ├── AnnotationModels.dart # 标注数据模型（HBB/OBB/SEG）
│       ├── ShortcutModels.dart  # 快捷键配置模型
│       ├── ConfigStore.dart     # 配置读写
│       ├── SettingsDialog.dart  # 设置弹窗
│       ├── FloatingMessage.dart # 浮动提示组件
│       └── language/           # 多语言 JSON 资源
└── models/                     # YOLO 模型文件（.pt / .onnx）
```

## 编译步骤

### 环境要求

- Windows 11（或 Windows 10）
- Rust 1.95+（通过 [rustup](https://rustup.rs) 安装）
- Flutter 3.44+（通过 [flutter.dev](https://flutter.dev) 安装）
- Visual Studio 2022（含"使用 C++ 的桌面开发"工作负载，用于编译 Windows 原生代码）

### 1. 生成 Flutter Rust Bridge 代码

```bash
# 在项目根目录执行
flutter_rust_bridge_codegen generate
```

此命令根据 `flutter_rust_bridge.yaml` 配置，从 `src/api.rs` 生成 Dart 绑定代码到 `flutter/lib/src/rust/`。

### 2. 编译 Rust

```bash
# Debug 模式
cargo build

# Release 模式
cargo build --release
```

### 3. 运行 Flutter 应用

```bash
cd flutter

# 获取依赖
flutter pub get

# Debug 运行（Windows）
flutter run -d windows

# Release 构建
flutter build windows
```

### 4. 使用 Rust 启动器（可选）

项目包含一个 Rust 启动器（`src/main.rs`），可自动构建 Rust 并启动 Flutter Windows GUI：

```bash
cargo run
```

## 配置文件

配置文件存储在 `%USERPROFILE%\.rustlabel\` 目录下：

- `history.json` — 最近打开的文件和文件夹
- `keybindings.json` — 自定义快捷键
- `settings.json` — Python 环境路径、训练结果保存位置

## 更多信息

详细功能说明见 [FEATURES.md](FEATURES.md)。
