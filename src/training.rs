use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use super::ini_python;
use once_cell::sync::Lazy;

static ACTIVE_HANDLE: Lazy<Mutex<Option<JoinHandle<()>>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_RUN_DIR: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_STOP_FILE: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_STATUS: Lazy<Mutex<String>> = Lazy::new(|| Mutex::new("idle".to_string()));
static ACTIVE_ERROR: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_TOTAL_EPOCHS: Lazy<Mutex<u32>> = Lazy::new(|| Mutex::new(0));
static ACTIVE_STARTED_AT: Lazy<Mutex<Option<Instant>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_LOG_PATH: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_LAST_LOG_HEARTBEAT: Lazy<Mutex<Option<Instant>>> = Lazy::new(|| Mutex::new(None));

const TRAINING_CODE: &str = r#"
import os
import sys
import time

class _RustLabelTee:
    def __init__(self, original, sink):
        self.original = original
        self.sink = sink

    def write(self, text):
        if not text:
            return 0
        try:
            self.sink.write(text)
            self.sink.flush()
        except Exception:
            pass
        try:
            self.original.write(text)
            self.original.flush()
        except Exception:
            pass
        return len(text)

    def flush(self):
        try:
            self.sink.flush()
        except Exception:
            pass
        try:
            self.original.flush()
        except Exception:
            pass

os.makedirs(os.path.dirname(log_path), exist_ok=True)
_rustlabel_log_stream = open(log_path, "a", encoding="utf-8", buffering=1)
sys.stdout = _RustLabelTee(sys.stdout, _rustlabel_log_stream)
sys.stderr = _RustLabelTee(sys.stderr, _rustlabel_log_stream)

python_exe_dir = os.path.dirname(python_path)
python_root = python_exe_dir
if os.path.basename(python_exe_dir).lower() == "scripts":
    python_root = os.path.dirname(python_exe_dir)
worker_python_path = python_path
if os.name == "nt":
    pythonw_path = os.path.join(python_exe_dir, "pythonw.exe")
    if os.path.isfile(pythonw_path):
        worker_python_path = pythonw_path

print("[rustlabel] Python training bootstrap")
print(f"[rustlabel] python_path={python_path}")
print(f"[rustlabel] worker_python_path={worker_python_path}")
print(f"[rustlabel] python_root={python_root}")
print(f"[rustlabel] model_path={model_path}")
print(f"[rustlabel] data_yaml_path={data_yaml_path}")
print(f"[rustlabel] project_dir={project_dir}")
print(f"[rustlabel] experiment_name={experiment_name}")
print(f"[rustlabel] epochs={epochs}, imgsz={imgsz}, batch={batch}, device={device}, resume={resume}")
print(
    "[rustlabel] train params: "
    f"workers={workers}, amp={amp}, cls_pw={cls_pw}, patience={patience}, "
    f"lr0={lr0}, momentum={momentum}"
)
print(
    "[rustlabel] augment params: "
    f"hsv_h={hsv_h}, hsv_s={hsv_s}, hsv_v={hsv_v}, translate={translate}, "
    f"scale={scale}, shear={shear}, flipud={flipud}, fliplr={fliplr}, "
    f"degrees={degrees}, perspective={perspective}, bgr={bgr}, mosaic={mosaic}, "
    f"mixup={mixup}, cutmix={cutmix}, copy_paste={copy_paste}, "
    f"copy_paste_mode={copy_paste_mode}, auto_augment={auto_augment}, erasing={erasing}"
)
print("[rustlabel] loss names: detect/obb => box, cls, dfl; seg => box, seg, cls, dfl; pose => box, pose, kobj, cls, dfl")
print("[rustlabel] progress format: epoch=... gpu=... box=..., cls=..., dfl=... batch=... size=... progress step=... speed=... elapsed=... eta=...")

site_candidates = [
    os.path.join(python_root, "Lib", "site-packages"),
    os.path.join(python_root, "lib", "site-packages"),
    os.path.join(python_root, "Lib"),
    python_root,
]
for item in reversed(site_candidates):
    if item and os.path.isdir(item) and item not in sys.path:
        sys.path.insert(0, item)

path_candidates = [
    python_exe_dir,
    python_root,
    os.path.join(python_root, "Scripts"),
    os.path.join(python_root, "Library", "bin"),
    os.path.join(python_root, "DLLs"),
]
existing_path = os.environ.get("PATH", "")
os.environ["PATH"] = os.pathsep.join(
    [item for item in path_candidates if os.path.isdir(item)] + [existing_path]
)
os.environ["ULTRALYTICS_TQDM"] = "false"
os.environ["CONDA_PREFIX"] = python_root
os.environ["CONDA_DLL_SEARCH_MODIFICATION_ENABLE"] = "1"

_rustlabel_dll_handles = []
if hasattr(os, "add_dll_directory"):
    for item in path_candidates:
        if item and os.path.isdir(item):
            try:
                _rustlabel_dll_handles.append(os.add_dll_directory(item))
                print(f"[rustlabel] added dll directory={item}")
            except Exception as error:
                print(f"[rustlabel] add_dll_directory failed: {item}: {error}")

print(f"[rustlabel] sys.path={sys.path}")
print(f"[rustlabel] PATH prefix={os.environ.get('PATH', '')[:1000]}")

try:
    import multiprocessing as _rustlabel_multiprocessing
    import multiprocessing.spawn as _rustlabel_multiprocessing_spawn
    sys.executable = worker_python_path
    if hasattr(sys, "_base_executable"):
        sys._base_executable = worker_python_path
    _rustlabel_multiprocessing.freeze_support()
    _rustlabel_multiprocessing.set_executable(worker_python_path)
    print(f"[rustlabel] multiprocessing executable={_rustlabel_multiprocessing_spawn.get_executable()}")
except Exception as error:
    print(f"[rustlabel] configure multiprocessing executable failed: {error}")

print("[rustlabel] importing ultralytics.YOLO")
from ultralytics import YOLO
print("[rustlabel] ultralytics import complete")

_rustlabel_last_progress_log = 0.0
_rustlabel_batch_index = 0
_rustlabel_epoch_started_at = 0.0
_rustlabel_args_cache = None

def _rustlabel_log(message):
    print(f"[rustlabel] {message}", flush=True)

def _rustlabel_run_dir():
    if resume:
        weights_dir = os.path.dirname(model_path)
        if os.path.basename(weights_dir).lower() == "weights":
            return os.path.dirname(weights_dir)
    return os.path.join(project_dir, experiment_name)

def _rustlabel_args_yaml_value(key):
    global _rustlabel_args_cache
    if _rustlabel_args_cache is None:
        _rustlabel_args_cache = {}
        args_path = os.path.join(_rustlabel_run_dir(), "args.yaml")
        try:
            with open(args_path, "r", encoding="utf-8") as file:
                for raw_line in file:
                    line = raw_line.split(chr(35), 1)[0].strip()
                    if not line or ":" not in line:
                        continue
                    item_key, item_value = line.split(":", 1)
                    _rustlabel_args_cache[item_key.strip()] = item_value.strip().strip("'\"")
        except Exception:
            pass
    return _rustlabel_args_cache.get(key)

def _parse_batch(value):
    text = str(value).strip()
    try:
        if "." in text:
            return float(text)
        return int(text)
    except Exception:
        return text

def _rustlabel_stop_callback(trainer):
    if os.path.exists(stop_file):
        raise KeyboardInterrupt("Training stopped by RustLabel")

def _rustlabel_model_task():
    try:
        return str(getattr(model, "task", "") or "").lower()
    except Exception:
        return ""

def _rustlabel_loss_names(values):
    task = _rustlabel_model_task()
    if len(values) == 3:
        return ["box", "cls", "dfl"]
    if len(values) == 4:
        if task in ("segment", "seg"):
            return ["box", "seg", "cls", "dfl"]
        return ["box", "cls", "dfl", "extra"]
    if len(values) == 5 and task == "pose":
        return ["box", "pose", "kobj", "cls", "dfl"]
    return [f"loss{i + 1}" for i in range(len(values))]

def _rustlabel_loss_text(trainer):
    try:
        loss = getattr(trainer, "tloss", None)
        if loss is None:
            return ""
        if hasattr(loss, "detach"):
            loss = loss.detach().cpu().tolist()
        if isinstance(loss, (list, tuple)):
            values = [float(item) for item in loss]
            names = _rustlabel_loss_names(values)
            pairs = ", ".join(
                f"{name}={value:.4f}" for name, value in zip(names, values)
            )
            return f" loss({pairs})"
        return f" loss(total={float(loss):.4f})"
    except Exception:
        return ""

def _rustlabel_loss_named_text(trainer):
    values = _rustlabel_loss_values(trainer)
    if not values:
        return "loss=unknown"
    names = _rustlabel_loss_names(values)
    return ", ".join(
        f"{name}={value:.4f}" for name, value in zip(names, values)
    )

def _rustlabel_loss_values(trainer):
    try:
        loss = getattr(trainer, "tloss", None)
        if loss is None:
            return []
        if hasattr(loss, "detach"):
            loss = loss.detach().cpu().tolist()
        if isinstance(loss, (list, tuple)):
            return [float(item) for item in loss]
        return [float(loss)]
    except Exception:
        return []

def _rustlabel_epoch_text(trainer):
    epoch = getattr(trainer, "epoch", None)
    epochs = getattr(trainer, "epochs", None)
    if isinstance(epoch, int) and isinstance(epochs, int):
        return f"{epoch + 1}/{epochs}"
    if isinstance(epoch, int):
        return str(epoch + 1)
    return "?"

def _rustlabel_batch_text(trainer):
    try:
        batch_i = getattr(trainer, "batch_i", None)
        loader = getattr(trainer, "train_loader", None)
        total = len(loader) if loader is not None else None
        index = batch_i if isinstance(batch_i, int) else _rustlabel_batch_index - 1
        if isinstance(batch_i, int) and isinstance(total, int) and total > 0:
            return f" batch={batch_i + 1}/{total}"
        if isinstance(index, int) and index >= 0 and isinstance(total, int) and total > 0:
            return f" batch={index + 1}/{total}"
        if isinstance(index, int) and index >= 0:
            return f" batch={index + 1}"
    except Exception:
        pass
    return ""

def _rustlabel_batch_position(trainer):
    try:
        batch_i = getattr(trainer, "batch_i", None)
        loader = getattr(trainer, "train_loader", None)
        total = len(loader) if loader is not None else None
        index = batch_i if isinstance(batch_i, int) else _rustlabel_batch_index - 1
        if not isinstance(index, int) or index < 0:
            index = 0
        return index + 1, total if isinstance(total, int) and total > 0 else None
    except Exception:
        return max(1, _rustlabel_batch_index), None

def _rustlabel_lr_text(trainer):
    try:
        optimizer = getattr(trainer, "optimizer", None)
        groups = getattr(optimizer, "param_groups", None)
        if not groups:
            return ""
        values = []
        for group in groups:
            lr = group.get("lr", None) if isinstance(group, dict) else None
            if isinstance(lr, (int, float)):
                values.append(float(lr))
        if not values:
            return ""
        if len(values) == 1:
            return f" lr={values[0]:.6g}"
        return " lr=[" + ", ".join(f"{value:.6g}" for value in values) + "]"
    except Exception:
        return ""

def _rustlabel_gpu_mem_value():
    try:
        import torch
        if not torch.cuda.is_available():
            return "0G"
        reserved = torch.cuda.memory_reserved() / 1024 / 1024 / 1024
        allocated = torch.cuda.memory_allocated() / 1024 / 1024 / 1024
        value = max(reserved, allocated)
        return f"{value:.2f}G"
    except Exception:
        return "0G"

def _rustlabel_gpu_text():
    try:
        import torch
        if not torch.cuda.is_available():
            return ""
        allocated = torch.cuda.memory_allocated() / 1024 / 1024 / 1024
        reserved = torch.cuda.memory_reserved() / 1024 / 1024 / 1024
        return f" gpu_mem={allocated:.2f}G/{reserved:.2f}G"
    except Exception:
        return ""

def _rustlabel_batch_size_text(trainer):
    try:
        value = getattr(trainer, "batch_size", None)
        if value is not None:
            return str(value)
        args = getattr(trainer, "args", None)
        value = getattr(args, "batch", None)
        if value is not None:
            return str(value)
        value = _rustlabel_args_yaml_value("batch")
        if value:
            return str(value)
        return str(batch)
    except Exception:
        value = _rustlabel_args_yaml_value("batch")
        return str(value) if value else str(batch)

def _rustlabel_progress_bar(done, total):
    if not total or total <= 0:
        return "----------"
    ratio = max(0.0, min(1.0, done / total))
    filled = int(round(ratio * 12))
    return "━" * filled + "─" * (12 - filled)

def _rustlabel_duration_text(seconds):
    seconds = max(0.0, float(seconds))
    if seconds >= 3600:
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        return f"{hours}h{minutes:02d}m"
    if seconds >= 60:
        minutes = int(seconds // 60)
        rest = int(seconds % 60)
        return f"{minutes}m{rest:02d}s"
    return f"{seconds:.1f}s"

def _rustlabel_speed_time_text(done, total):
    if _rustlabel_epoch_started_at <= 0:
        return "speed=0.0it/s elapsed=0.0s eta=unknown"
    elapsed = max(0.001, time.time() - _rustlabel_epoch_started_at)
    speed = done / elapsed
    if total and total > done and speed > 0:
        eta = (total - done) / speed
        eta_text = _rustlabel_duration_text(eta)
    else:
        eta_text = "0.0s"
    return (
        f"speed={speed:.1f}it/s "
        f"elapsed={_rustlabel_duration_text(elapsed)} "
        f"eta={eta_text}"
    )

def _rustlabel_native_progress_text(trainer):
    done, total = _rustlabel_batch_position(trainer)
    if total:
        percent = int(round(max(0.0, min(1.0, done / total)) * 100))
        batch_text = f"{done}/{total}"
    else:
        percent = 0
        batch_text = str(done)
    return (
        f"epoch={_rustlabel_epoch_text(trainer)} "
        f"gpu={_rustlabel_gpu_mem_value()} "
        f"{_rustlabel_loss_named_text(trainer)} "
        f"batch={_rustlabel_batch_size_text(trainer)} "
        f"size={imgsz}: "
        f"{percent:3d}% {_rustlabel_progress_bar(done, total)} "
        f"step={batch_text} {_rustlabel_speed_time_text(done, total)}"
    )

def _rustlabel_metric_float(value):
    try:
        if value is None:
            return None
        if hasattr(value, "detach"):
            value = value.detach().cpu()
        if hasattr(value, "item"):
            value = value.item()
        return float(value)
    except Exception:
        return None

def _rustlabel_metric_from_dict(values, keys):
    if not isinstance(values, dict):
        return None
    for key in keys:
        if key in values:
            number = _rustlabel_metric_float(values.get(key))
            if number is not None:
                return number
    return None

def _rustlabel_metric_from_object(values, attrs):
    if values is None:
        return None
    for attr in attrs:
        if hasattr(values, attr):
            number = _rustlabel_metric_float(getattr(values, attr))
            if number is not None:
                return number
    return None

def _rustlabel_metric_value(metrics, dict_keys, object_attrs):
    number = _rustlabel_metric_from_dict(metrics, dict_keys)
    if number is not None:
        return number
    number = _rustlabel_metric_from_object(metrics, object_attrs)
    if number is not None:
        return number
    for child_name in ("box", "seg", "obb", "pose"):
        child = getattr(metrics, child_name, None)
        number = _rustlabel_metric_from_object(child, object_attrs)
        if number is not None:
            return number
    return None

def _rustlabel_metrics_text(trainer):
    try:
        metrics = getattr(trainer, "metrics", None)
        if not metrics:
            validator = getattr(trainer, "validator", None)
            metrics = getattr(validator, "metrics", None)
        precision = _rustlabel_metric_value(
            metrics,
            ["metrics/precision(B)", "metrics/precision(M)", "metrics/precision(O)", "metrics/precision"],
            ["precision", "mp"],
        )
        recall = _rustlabel_metric_value(
            metrics,
            ["metrics/recall(B)", "metrics/recall(M)", "metrics/recall(O)", "metrics/recall"],
            ["recall", "mr"],
        )
        map50 = _rustlabel_metric_value(
            metrics,
            ["metrics/mAP50(B)", "metrics/mAP50(M)", "metrics/mAP50(O)", "metrics/mAP_0.5", "metrics/mAP50"],
            ["map50"],
        )
        map5095 = _rustlabel_metric_value(
            metrics,
            ["metrics/mAP50-95(B)", "metrics/mAP50-95(M)", "metrics/mAP50-95(O)", "metrics/mAP_0.5:0.95", "metrics/mAP50-95"],
            ["map", "map5095", "map50_95"],
        )
        pairs = []
        if precision is not None:
            pairs.append(f"precision={precision:.4f}")
        if recall is not None:
            pairs.append(f"recall={recall:.4f}")
        if map50 is not None:
            pairs.append(f"mAP50={map50:.4f}")
        if map5095 is not None:
            pairs.append(f"mAP50-95={map5095:.4f}")
        return " metrics(" + ", ".join(pairs) + ")" if pairs else ""
    except Exception:
        return ""

def _rustlabel_epoch_time_text():
    if _rustlabel_epoch_started_at <= 0:
        return ""
    elapsed = max(0.0, time.time() - _rustlabel_epoch_started_at)
    return f" epoch_time={elapsed:.1f}s"

def _rustlabel_train_start_callback(trainer):
    _rustlabel_log("train start callback reached")
    _rustlabel_stop_callback(trainer)

def _rustlabel_epoch_start_callback(trainer):
    global _rustlabel_batch_index, _rustlabel_epoch_started_at
    _rustlabel_batch_index = 0
    _rustlabel_epoch_started_at = time.time()
    _rustlabel_log(
        f"epoch {_rustlabel_epoch_text(trainer)} start"
        f"{_rustlabel_lr_text(trainer)}"
    )
    _rustlabel_stop_callback(trainer)

def _rustlabel_progress_callback(trainer):
    global _rustlabel_last_progress_log
    _rustlabel_stop_callback(trainer)
    now = time.time()
    if now - _rustlabel_last_progress_log < 1.0:
        return
    _rustlabel_last_progress_log = now
    _rustlabel_log(_rustlabel_native_progress_text(trainer))

def _rustlabel_batch_end_callback(trainer):
    global _rustlabel_batch_index
    _rustlabel_batch_index += 1
    _rustlabel_progress_callback(trainer)

def _rustlabel_epoch_end_callback(trainer):
    _rustlabel_log(
        f"epoch {_rustlabel_epoch_text(trainer)} end"
        f"{_rustlabel_loss_text(trainer)}"
        f"{_rustlabel_metrics_text(trainer)}"
        f"{_rustlabel_lr_text(trainer)}"
        f"{_rustlabel_gpu_text()}"
        f"{_rustlabel_epoch_time_text()}"
    )
    _rustlabel_stop_callback(trainer)

def _rustlabel_fit_epoch_end_callback(trainer):
    _rustlabel_log(
        f"validation epoch={_rustlabel_epoch_text(trainer)}"
        f"{_rustlabel_metrics_text(trainer)}"
        f"{_rustlabel_lr_text(trainer)}"
        f"{_rustlabel_gpu_text()}"
    )
    _rustlabel_stop_callback(trainer)

print("[rustlabel] loading model")
model = YOLO(model_path)
print("[rustlabel] model loaded")
try:
    model.add_callback("on_train_start", _rustlabel_train_start_callback)
    model.add_callback("on_train_epoch_start", _rustlabel_epoch_start_callback)
    model.add_callback("on_train_batch_end", _rustlabel_batch_end_callback)
    model.add_callback("on_train_epoch_end", _rustlabel_epoch_end_callback)
    model.add_callback("on_fit_epoch_end", _rustlabel_fit_epoch_end_callback)
except Exception as error:
    _rustlabel_log(f"register callbacks failed: {error}")

if cls_pw > 0 and hasattr(model, "cls_pw"):
    model.cls_pw = cls_pw

if resume:
    print("[rustlabel] calling model.train(resume=True)")
    model.train(resume=True)
else:
    print("[rustlabel] calling model.train(...)")
    model.train(
        data=data_yaml_path,
        epochs=epochs,
        imgsz=imgsz,
        batch=_parse_batch(batch),
        device=device,
        lr0=lr0,
        momentum=momentum,
        patience=patience,
        hsv_h=hsv_h,
        hsv_s=hsv_s,
        hsv_v=hsv_v,
        translate=translate,
        scale=scale,
        shear=shear,
        flipud=flipud,
        fliplr=fliplr,
        degrees=degrees,
        perspective=perspective,
        bgr=bgr,
        mosaic=mosaic,
        mixup=mixup,
        cutmix=cutmix,
        copy_paste=copy_paste,
        copy_paste_mode=copy_paste_mode,
        auto_augment=auto_augment,
        erasing=erasing,
        workers=workers,
        amp=amp,
        project=project_dir,
        name=experiment_name,
        exist_ok=True,
    )
print("[rustlabel] training call finished")
"#;

#[derive(Debug, Clone)]
pub struct TrainingConfig {
    pub python_path: String,
    pub model_path: String,
    pub data_yaml_path: String,
    pub project_dir: String,
    pub experiment_name: String,
    pub epochs: u32,
    pub imgsz: u32,
    pub batch: String,
    pub device: String,
    pub lr0: f64,
    pub momentum: f64,
    pub patience: u32,
    pub hsv_h: f64,
    pub hsv_s: f64,
    pub hsv_v: f64,
    pub translate: f64,
    pub scale: f64,
    pub shear: f64,
    pub flipud: f64,
    pub fliplr: f64,
    pub degrees: f64,
    pub perspective: f64,
    pub bgr: f64,
    pub mosaic: f64,
    pub mixup: f64,
    pub cutmix: f64,
    pub copy_paste: f64,
    pub copy_paste_mode: String,
    pub auto_augment: String,
    pub erasing: f64,
    pub workers: u32,
    pub amp: bool,
    pub resume: bool,
    pub cls_pw: f64,
}

#[derive(Debug, Clone)]
pub struct TrainingProgress {
    pub current_epoch: u32,
    pub total_epochs: u32,
    pub status: String,
    pub train_loss: Option<f64>,
    pub val_loss: Option<f64>,
    pub map50: Option<f64>,
    pub map50_95: Option<f64>,
    pub precision: Option<f64>,
    pub recall: Option<f64>,
    pub lr: Option<f64>,
    pub elapsed_seconds: f64,
    pub estimated_remaining_seconds: f64,
}

pub fn start_training(mut config: TrainingConfig) -> Result<String, String> {
    cleanup_finished_training();
    if ACTIVE_HANDLE.lock().unwrap().is_some() {
        return Err("Training is already running or stopping".to_string());
    }

    config.python_path = ini_python::verify_python_path(&config.python_path)?;
    let log_path = training_log_path()?;
    append_log_line(&log_path, "training start requested");
    append_log_line(&log_path, &format!("python_path={}", config.python_path));
    append_log_line(&log_path, &format!("model_path={}", config.model_path));
    append_log_line(
        &log_path,
        &format!("data_yaml_path={}", config.data_yaml_path),
    );
    append_log_line(&log_path, &format!("project_dir={}", config.project_dir));
    append_log_line(
        &log_path,
        &format!("experiment_name={}", config.experiment_name),
    );

    let project = PathBuf::from(config.project_dir.trim());
    if config.project_dir.trim().is_empty() {
        append_log_line(&log_path, "training output path is empty");
        return Err("Training output path is empty".to_string());
    }
    fs::create_dir_all(&project).map_err(|error| format!("create project dir: {error}"))?;

    let run_dir = expected_run_dir(&config, &project);
    let stop_file = project.join(format!(
        ".rustlabel_stop_{}.flag",
        unix_millis_now().unwrap_or(0)
    ));
    let _ = fs::remove_file(&stop_file);

    set_status("running", None);
    *ACTIVE_RUN_DIR.lock().unwrap() = Some(run_dir.to_string_lossy().into_owned());
    *ACTIVE_STOP_FILE.lock().unwrap() = Some(stop_file.to_string_lossy().into_owned());
    *ACTIVE_TOTAL_EPOCHS.lock().unwrap() = config.epochs;
    *ACTIVE_STARTED_AT.lock().unwrap() = Some(Instant::now());
    *ACTIVE_LOG_PATH.lock().unwrap() = Some(log_path.to_string_lossy().into_owned());
    *ACTIVE_LAST_LOG_HEARTBEAT.lock().unwrap() = None;
    append_log_line(
        &log_path,
        &format!("expected_run_dir={}", run_dir.display()),
    );

    let thread_stop_file = stop_file.clone();
    let thread_log_path = log_path.clone();
    let handle = thread::spawn(move || {
        append_log_line(&thread_log_path, "training thread started");
        let result = run_training_thread(&config, &thread_stop_file, &thread_log_path);
        match result {
            Ok(()) => {
                append_log_line(&thread_log_path, "training completed");
                set_status("completed", None)
            }
            Err(error) if thread_stop_file.exists() || error.contains("KeyboardInterrupt") => {
                append_log_line(&thread_log_path, "training stopped by user");
                set_status("stopped", None);
            }
            Err(error) => {
                append_log_line(&thread_log_path, &format!("training error: {error}"));
                set_status("error", Some(error));
            }
        }
        let _ = fs::remove_file(&thread_stop_file);
    });
    *ACTIVE_HANDLE.lock().unwrap() = Some(handle);

    Ok(run_dir.to_string_lossy().into_owned())
}

pub fn preload_yolo_python(python_path: &str) -> Result<String, String> {
    ini_python::initialize_python(python_path)?;
    let log_path = training_log_path().ok();
    if let Some(path) = &log_path {
        append_log_line(path, "python preload requested");
    }
    preload_training_modules_opt(log_path.as_deref())?;
    Ok("Python YOLO runtime preloaded".to_string())
}

pub fn poll_training_progress() -> Option<TrainingProgress> {
    cleanup_finished_training();
    let run_dir = ACTIVE_RUN_DIR.lock().unwrap().clone()?;
    let status = ACTIVE_STATUS.lock().unwrap().clone();
    let total_epochs = *ACTIVE_TOTAL_EPOCHS.lock().unwrap();
    let results_path = PathBuf::from(&run_dir).join("results.csv");
    let mut current_epoch = 0_u32;
    let mut metrics = (None, None, None, None, None, None, None);

    if results_path.exists() {
        if let (Some(columns), Some(line)) = (
            read_results_csv_columns(&results_path),
            read_last_csv_line(&results_path),
        ) {
            let values: Vec<&str> = line.split(',').map(str::trim).collect();
            let map: HashMap<&str, f64> = columns
                .iter()
                .zip(values.iter())
                .filter_map(|(key, value)| value.parse::<f64>().ok().map(|n| (key.as_str(), n)))
                .collect();

            let csv_epoch = map.get("epoch").copied().unwrap_or(0.0).max(0.0) as u32;
            current_epoch = csv_epoch.saturating_add(1);
            metrics = (
                map.get("train/box_loss").or(map.get("train/loss")).copied(),
                map.get("val/box_loss").or(map.get("val/loss")).copied(),
                map.get("metrics/mAP50(B)")
                    .or(map.get("metrics/mAP_0.5"))
                    .copied(),
                map.get("metrics/mAP50-95(B)")
                    .or(map.get("metrics/mAP_0.5:0.95"))
                    .copied(),
                map.get("metrics/precision(B)")
                    .or(map.get("metrics/precision"))
                    .copied(),
                map.get("metrics/recall(B)")
                    .or(map.get("metrics/recall"))
                    .copied(),
                map.get("lr/pg0").or(map.get("lr/0")).copied(),
            );
        }
    }

    let total = total_epochs.max(current_epoch);
    let elapsed = active_elapsed_seconds().unwrap_or_else(|| compute_elapsed_seconds(&run_dir));
    let remaining = if current_epoch > 0 && total > current_epoch {
        elapsed / current_epoch as f64 * (total - current_epoch) as f64
    } else {
        0.0
    };
    let error = ACTIVE_ERROR.lock().unwrap().clone();
    let status = if status == "error" {
        error
            .map(|value| format!("error: {value}"))
            .unwrap_or_else(|| "error".to_string())
    } else if status == "idle" && results_path.exists() {
        "completed".to_string()
    } else {
        status
    };
    append_running_heartbeat(&status, current_epoch, total);

    Some(TrainingProgress {
        current_epoch,
        total_epochs: total,
        status,
        train_loss: metrics.0,
        val_loss: metrics.1,
        map50: metrics.2,
        map50_95: metrics.3,
        precision: metrics.4,
        recall: metrics.5,
        lr: metrics.6,
        elapsed_seconds: elapsed,
        estimated_remaining_seconds: remaining,
    })
}

pub fn stop_training() -> Result<String, String> {
    cleanup_finished_training();
    if ACTIVE_HANDLE.lock().unwrap().is_none() {
        return Ok("No training in progress".to_string());
    }

    let stop_file = ACTIVE_STOP_FILE.lock().unwrap().clone();
    if let Some(path) = stop_file {
        fs::write(&path, "stop").map_err(|error| format!("request stop: {error}"))?;
        if let Some(log_path) = ACTIVE_LOG_PATH.lock().unwrap().clone() {
            append_log_line(Path::new(&log_path), "stop requested");
        }
        set_status("stopping", None);
        Ok("Training stop requested".to_string())
    } else {
        Err("Stop file is not available".to_string())
    }
}

pub fn shutdown_training(timeout_ms: u64) -> Result<String, String> {
    let message = stop_training()?;
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    loop {
        cleanup_finished_training();
        if ACTIVE_HANDLE.lock().unwrap().is_none() {
            return Ok(format!("{message}; training stopped"));
        }
        if Instant::now() >= deadline {
            return Ok(format!("{message}; training is still stopping"));
        }
        thread::sleep(Duration::from_millis(100));
    }
}

pub fn training_log_tail(max_chars: usize) -> Result<(String, String), String> {
    let path = ACTIVE_LOG_PATH
        .lock()
        .unwrap()
        .clone()
        .map(PathBuf::from)
        .or_else(|| training_log_path().ok())
        .ok_or_else(|| "Training log path is not available".to_string())?;
    let text = fs::read_to_string(&path)
        .map_err(|error| format!("read training log {}: {error}", path.display()))?;
    let max_chars = max_chars.max(1024);
    let tail = if text.chars().count() <= max_chars {
        text
    } else {
        let total = text.chars().count();
        text.chars().skip(total - max_chars).collect()
    };
    Ok((path.to_string_lossy().into_owned(), tail))
}

pub fn training_log_dates_json() -> Result<String, String> {
    let directory = training_logs_directory()?;
    let mut dates = Vec::new();
    if directory.exists() {
        for entry in fs::read_dir(&directory)
            .map_err(|error| format!("read logs dir {}: {error}", directory.display()))?
        {
            let entry = entry.map_err(|error| error.to_string())?;
            let path = entry.path();
            if path.extension().and_then(|value| value.to_str()) != Some("log") {
                continue;
            }
            let Some(stem) = path.file_stem().and_then(|value| value.to_str()) else {
                continue;
            };
            if is_safe_log_date(stem) {
                dates.push(stem.to_string());
            }
        }
    }
    dates.sort_by(|a, b| b.cmp(a));
    Ok(string_array_json("dates", &dates))
}

pub fn read_training_log_for_date_json(date: &str) -> Result<String, String> {
    let date = safe_log_date(date)?;
    let path = training_logs_directory()?.join(format!("{date}.log"));
    let text = if path.exists() {
        fs::read_to_string(&path)
            .map_err(|error| format!("read training log {}: {error}", path.display()))?
    } else {
        String::new()
    };
    Ok(format!(
        "{{\"ok\":true,\"date\":\"{}\",\"path\":\"{}\",\"text\":\"{}\"}}",
        json_escape(&date),
        json_escape(&path.to_string_lossy()),
        json_escape(&text)
    ))
}

pub fn delete_training_logs_by_date_range_json(
    start_date: &str,
    end_date: &str,
) -> Result<String, String> {
    let start_date = safe_log_date(start_date)?;
    let end_date = safe_log_date(end_date)?;
    let (start, end) = if start_date <= end_date {
        (start_date, end_date)
    } else {
        (end_date, start_date)
    };
    let directory = training_logs_directory()?;
    let mut deleted = 0usize;
    if directory.exists() {
        for entry in fs::read_dir(&directory)
            .map_err(|error| format!("read logs dir {}: {error}", directory.display()))?
        {
            let entry = entry.map_err(|error| error.to_string())?;
            let path = entry.path();
            if path.extension().and_then(|value| value.to_str()) != Some("log") {
                continue;
            }
            let Some(stem) = path.file_stem().and_then(|value| value.to_str()) else {
                continue;
            };
            if is_safe_log_date(stem) && stem >= start.as_str() && stem <= end.as_str() {
                fs::remove_file(&path)
                    .map_err(|error| format!("delete training log {}: {error}", path.display()))?;
                deleted += 1;
            }
        }
    }
    Ok(format!("{{\"ok\":true,\"deleted\":{deleted}}}"))
}

fn run_training_thread(
    config: &TrainingConfig,
    stop_file: &Path,
    log_path: &Path,
) -> Result<(), String> {
    append_log_line(log_path, "python runtime configure starting");
    if let Err(error) = ini_python::configure_python_runtime(&config.python_path) {
        append_log_line(
            log_path,
            &format!("python runtime configure failed: {error}"),
        );
        return Err(error);
    }
    append_log_line(log_path, "python runtime configured");

    append_log_line(log_path, "python modules preload starting");
    if let Err(error) = preload_training_modules(log_path) {
        append_log_line(log_path, &format!("python preload warning: {error}"));
    }

    run_training_with_embedded_python(config, stop_file, log_path)
}

fn run_training_with_embedded_python(
    config: &TrainingConfig,
    stop_file: &Path,
    log_path: &Path,
) -> Result<(), String> {
    let code = training_code_with_locals(config, stop_file, log_path);
    ini_python::run_python_code(&code)
}

fn training_code_with_locals(config: &TrainingConfig, stop_file: &Path, log_path: &Path) -> String {
    format!(
        concat!(
            "python_path = {}\n",
            "model_path = {}\n",
            "data_yaml_path = {}\n",
            "project_dir = {}\n",
            "experiment_name = {}\n",
            "epochs = {}\n",
            "imgsz = {}\n",
            "batch = {}\n",
            "device = {}\n",
            "lr0 = {}\n",
            "momentum = {}\n",
            "patience = {}\n",
            "hsv_h = {}\n",
            "hsv_s = {}\n",
            "hsv_v = {}\n",
            "translate = {}\n",
            "scale = {}\n",
            "shear = {}\n",
            "flipud = {}\n",
            "fliplr = {}\n",
            "degrees = {}\n",
            "perspective = {}\n",
            "bgr = {}\n",
            "mosaic = {}\n",
            "mixup = {}\n",
            "cutmix = {}\n",
            "copy_paste = {}\n",
            "copy_paste_mode = {}\n",
            "auto_augment = {}\n",
            "erasing = {}\n",
            "workers = {}\n",
            "amp = {}\n",
            "resume = {}\n",
            "cls_pw = {}\n",
            "stop_file = {}\n",
            "log_path = {}\n\n",
            "{}"
        ),
        python_string_literal(&config.python_path),
        python_string_literal(&config.model_path),
        python_string_literal(&config.data_yaml_path),
        python_string_literal(&config.project_dir),
        python_string_literal(&config.experiment_name),
        config.epochs,
        config.imgsz,
        python_string_literal(&config.batch),
        python_string_literal(&config.device),
        finite_python_number(config.lr0),
        finite_python_number(config.momentum),
        config.patience,
        finite_python_number(config.hsv_h),
        finite_python_number(config.hsv_s),
        finite_python_number(config.hsv_v),
        finite_python_number(config.translate),
        finite_python_number(config.scale),
        finite_python_number(config.shear),
        finite_python_number(config.flipud),
        finite_python_number(config.fliplr),
        finite_python_number(config.degrees),
        finite_python_number(config.perspective),
        finite_python_number(config.bgr),
        finite_python_number(config.mosaic),
        finite_python_number(config.mixup),
        finite_python_number(config.cutmix),
        finite_python_number(config.copy_paste),
        python_string_literal(&config.copy_paste_mode),
        python_string_literal(&config.auto_augment),
        finite_python_number(config.erasing),
        config.workers,
        python_bool(config.amp),
        python_bool(config.resume),
        finite_python_number(config.cls_pw),
        python_string_literal(&stop_file.to_string_lossy()),
        python_string_literal(&log_path.to_string_lossy()),
        TRAINING_CODE
    )
}

fn python_string_literal(value: &str) -> String {
    let mut output = String::from("'");
    for ch in value.chars() {
        match ch {
            '\\' => output.push_str("\\\\"),
            '\'' => output.push_str("\\'"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            _ => output.push(ch),
        }
    }
    output.push('\'');
    output
}

fn python_bool(value: bool) -> &'static str {
    if value {
        "True"
    } else {
        "False"
    }
}

fn finite_python_number(value: f64) -> String {
    if value.is_finite() {
        value.to_string()
    } else {
        "0".to_string()
    }
}

fn preload_training_modules(log_path: &Path) -> Result<(), String> {
    let result = ini_python::preload_yolo_modules();
    match &result {
        Ok(()) => append_log_line(log_path, "python modules preloaded"),
        Err(error) => append_log_line(log_path, &format!("python modules preload failed: {error}")),
    }
    result
}

fn preload_training_modules_opt(log_path: Option<&Path>) -> Result<(), String> {
    let result = ini_python::preload_yolo_modules();
    if let (Ok(()), Some(path)) = (&result, log_path) {
        append_log_line(path, "python modules preloaded");
    }
    result
}

fn expected_run_dir(config: &TrainingConfig, project: &Path) -> PathBuf {
    if config.resume {
        if let Some(run_dir) = run_dir_from_checkpoint(&config.model_path) {
            return run_dir;
        }
    }
    project.join(config.experiment_name.trim())
}

fn run_dir_from_checkpoint(model_path: &str) -> Option<PathBuf> {
    let checkpoint = PathBuf::from(model_path);
    let weights = checkpoint.parent()?;
    if weights
        .file_name()?
        .to_string_lossy()
        .eq_ignore_ascii_case("weights")
    {
        return weights.parent().map(Path::to_path_buf);
    }
    None
}

fn set_status(status: &str, error: Option<String>) {
    *ACTIVE_STATUS.lock().unwrap() = status.to_string();
    *ACTIVE_ERROR.lock().unwrap() = error;
}

fn append_running_heartbeat(status: &str, current_epoch: u32, total_epochs: u32) {
    if status != "running" && status != "stopping" {
        return;
    }
    let now = Instant::now();
    {
        let mut last = ACTIVE_LAST_LOG_HEARTBEAT.lock().unwrap();
        if last
            .map(|value| now.duration_since(value) < Duration::from_secs(10))
            .unwrap_or(false)
        {
            return;
        }
        *last = Some(now);
    }
    if let Some(path) = ACTIVE_LOG_PATH.lock().unwrap().clone() {
        append_log_line(
            Path::new(&path),
            &format!(
                "training heartbeat: status={status}, epoch={}/{}; waiting for next trainer callback",
                current_epoch.max(1),
                total_epochs.max(current_epoch).max(1)
            ),
        );
    }
}

fn cleanup_finished_training() {
    let finished = ACTIVE_HANDLE
        .lock()
        .unwrap()
        .as_ref()
        .map(|handle| handle.is_finished())
        .unwrap_or(false);
    if !finished {
        return;
    }
    if let Some(handle) = ACTIVE_HANDLE.lock().unwrap().take() {
        let _ = handle.join();
    }
    *ACTIVE_STOP_FILE.lock().unwrap() = None;
    *ACTIVE_STARTED_AT.lock().unwrap() = None;
    *ACTIVE_LAST_LOG_HEARTBEAT.lock().unwrap() = None;
}

fn training_log_path() -> Result<PathBuf, String> {
    let directory = training_logs_directory()?;
    fs::create_dir_all(&directory)
        .map_err(|error| format!("create logs dir {}: {error}", directory.display()))?;
    Ok(directory.join(format!("{}.log", local_log_date_string())))
}

fn training_logs_directory() -> Result<PathBuf, String> {
    Ok(project_directory()?.join("logs"))
}

fn append_log_line(path: &Path, message: &str) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let timestamp = log_timestamp();
    if let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(path) {
        for line in message.lines() {
            let _ = writeln!(file, "[{timestamp}] {line}");
        }
    }
}

fn project_directory() -> Result<PathBuf, String> {
    let current = env::current_dir().map_err(|error| format!("current dir: {error}"))?;
    if file_name_eq(&current, "flutter") {
        return current
            .parent()
            .map(Path::to_path_buf)
            .ok_or_else(|| "Flutter directory has no parent".to_string());
    }
    Ok(current)
}

fn safe_log_date(value: &str) -> Result<String, String> {
    let trimmed = value.trim();
    if is_safe_log_date(trimmed) {
        Ok(trimmed.to_string())
    } else {
        Err(format!("Invalid log date: {value}"))
    }
}

fn is_safe_log_date(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() == 10
        && bytes[0..4].iter().all(u8::is_ascii_digit)
        && bytes[4] == b'-'
        && bytes[5..7].iter().all(u8::is_ascii_digit)
        && bytes[7] == b'-'
        && bytes[8..10].iter().all(u8::is_ascii_digit)
}

fn string_array_json(key: &str, values: &[String]) -> String {
    let mut output = format!("{{\"ok\":true,\"{}\":[", json_escape(key));
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push('"');
        output.push_str(&json_escape(value));
        output.push('"');
    }
    output.push_str("]}");
    output
}

fn json_escape(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '"' => escaped.push_str("\\\""),
            '\\' => escaped.push_str("\\\\"),
            '\n' => escaped.push_str("\\n"),
            '\r' => escaped.push_str("\\r"),
            '\t' => escaped.push_str("\\t"),
            ch if ch.is_control() => escaped.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => escaped.push(ch),
        }
    }
    escaped
}

fn local_log_date_string() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
        + 8 * 60 * 60;
    let days = seconds.div_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    format!("{year:04}-{month:02}-{day:02}")
}

fn log_timestamp() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
        + 8 * 60 * 60;
    let days = seconds.div_euclid(86_400);
    let seconds_of_day = seconds.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    let hour = seconds_of_day / 3600;
    let minute = seconds_of_day % 3600 / 60;
    let second = seconds_of_day % 60;
    format!("{year:04}-{month:02}-{day:02} {hour:02}:{minute:02}:{second:02}")
}

fn civil_from_days(days: i64) -> (i32, u32, u32) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    let year = year + if month <= 2 { 1 } else { 0 };
    (year as i32, month as u32, day as u32)
}

fn active_elapsed_seconds() -> Option<f64> {
    ACTIVE_STARTED_AT
        .lock()
        .unwrap()
        .map(|started| started.elapsed().as_secs_f64())
}

fn read_results_csv_columns(path: &Path) -> Option<Vec<String>> {
    let file = fs::File::open(path).ok()?;
    let reader = BufReader::new(file);
    let first_line = reader.lines().next()?.ok()?;
    let trimmed = first_line.trim().trim_start_matches('\u{feff}');
    if trimmed.is_empty() {
        return None;
    }
    Some(
        trimmed
            .split(',')
            .map(|value| value.trim().to_string())
            .collect(),
    )
}

fn read_last_csv_line(path: &Path) -> Option<String> {
    let file = fs::File::open(path).ok()?;
    let reader = BufReader::new(file);
    reader
        .lines()
        .map_while(Result::ok)
        .filter(|line| {
            let trimmed = line.trim();
            !trimmed.is_empty() && !trimmed.to_ascii_lowercase().starts_with("epoch")
        })
        .last()
}

fn compute_elapsed_seconds(run_dir: &str) -> f64 {
    let results = PathBuf::from(run_dir).join("results.csv");
    let metadata = match fs::metadata(&results) {
        Ok(value) => value,
        Err(_) => return 0.0,
    };
    let modified = match metadata.modified() {
        Ok(value) => value,
        Err(_) => return 0.0,
    };
    let created = match fs::metadata(run_dir).and_then(|value| value.created()) {
        Ok(value) => value,
        Err(_) => return 0.0,
    };
    modified
        .duration_since(created)
        .map(|duration| duration.as_secs_f64())
        .unwrap_or(0.0)
        .max(0.0)
}

fn unix_millis_now() -> Option<u128> {
    Some(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .ok()?
            .as_millis(),
    )
}

fn file_name_eq(path: &Path, expected: &str) -> bool {
    path.file_name()
        .map(|value| value.to_string_lossy().eq_ignore_ascii_case(expected))
        .unwrap_or(false)
}
