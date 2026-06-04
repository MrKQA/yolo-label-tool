use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::thread::{self, JoinHandle};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use once_cell::sync::Lazy;
use pyo3::prelude::*;
use pyo3::types::PyDict;

static ACTIVE_HANDLE: Lazy<Mutex<Option<JoinHandle<()>>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_RUN_DIR: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_STOP_FILE: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_STATUS: Lazy<Mutex<String>> = Lazy::new(|| Mutex::new("idle".to_string()));
static ACTIVE_ERROR: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_TOTAL_EPOCHS: Lazy<Mutex<u32>> = Lazy::new(|| Mutex::new(0));
static ACTIVE_STARTED_AT: Lazy<Mutex<Option<Instant>>> = Lazy::new(|| Mutex::new(None));
static ACTIVE_LOG_PATH: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));
static PYTHON_RUNTIME_HOME: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));

const TRAINING_CODE: &str = r#"
import os
import sys

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

print("[rustlabel] Python training bootstrap")
print(f"[rustlabel] python_path={python_path}")
print(f"[rustlabel] python_root={python_root}")
print(f"[rustlabel] model_path={model_path}")
print(f"[rustlabel] data_yaml_path={data_yaml_path}")
print(f"[rustlabel] project_dir={project_dir}")
print(f"[rustlabel] experiment_name={experiment_name}")
print(f"[rustlabel] epochs={epochs}, imgsz={imgsz}, batch={batch}, device={device}, resume={resume}")

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
    sys.executable = python_path
    if hasattr(sys, "_base_executable"):
        sys._base_executable = python_path
    _rustlabel_multiprocessing.freeze_support()
    _rustlabel_multiprocessing.set_executable(python_path)
    print(f"[rustlabel] multiprocessing executable={_rustlabel_multiprocessing_spawn.get_executable()}")
except Exception as error:
    print(f"[rustlabel] configure multiprocessing executable failed: {error}")

print("[rustlabel] importing ultralytics.YOLO")
from ultralytics import YOLO
print("[rustlabel] ultralytics import complete")

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

print("[rustlabel] loading model")
model = YOLO(model_path)
print("[rustlabel] model loaded")
try:
    model.add_callback("on_train_batch_end", _rustlabel_stop_callback)
    model.add_callback("on_train_epoch_end", _rustlabel_stop_callback)
except Exception:
    pass

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
        hsv_s=hsv_s,
        hsv_v=hsv_v,
        translate=translate,
        scale=scale,
        shear=shear,
        flipud=flipud,
        fliplr=fliplr,
        degrees=degrees,
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
    pub hsv_s: f64,
    pub hsv_v: f64,
    pub translate: f64,
    pub scale: f64,
    pub shear: f64,
    pub flipud: f64,
    pub fliplr: f64,
    pub degrees: f64,
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

    config.python_path = verify_python_path(&config.python_path)?;
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

    if let Err(error) = configure_python_runtime(&config.python_path) {
        append_log_line(
            &log_path,
            &format!("python runtime configure failed: {error}"),
        );
        return Err(error);
    }
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
    append_log_line(
        &log_path,
        &format!("expected_run_dir={}", run_dir.display()),
    );

    let thread_stop_file = stop_file.clone();
    let thread_log_path = log_path.clone();
    let handle = thread::spawn(move || {
        append_log_line(&thread_log_path, "training thread started");
        let result = run_training_with_pyo3(&config, &thread_stop_file, &thread_log_path);
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

fn run_training_with_pyo3(
    config: &TrainingConfig,
    stop_file: &Path,
    log_path: &Path,
) -> Result<(), String> {
    Python::with_gil(|py| -> PyResult<()> {
        let locals = PyDict::new_bound(py);
        locals.set_item("python_path", config.python_path.as_str())?;
        locals.set_item("model_path", config.model_path.as_str())?;
        locals.set_item("data_yaml_path", config.data_yaml_path.as_str())?;
        locals.set_item("project_dir", config.project_dir.as_str())?;
        locals.set_item("experiment_name", config.experiment_name.as_str())?;
        locals.set_item("epochs", config.epochs)?;
        locals.set_item("imgsz", config.imgsz)?;
        locals.set_item("batch", config.batch.as_str())?;
        locals.set_item("device", config.device.as_str())?;
        locals.set_item("lr0", config.lr0)?;
        locals.set_item("momentum", config.momentum)?;
        locals.set_item("hsv_s", config.hsv_s)?;
        locals.set_item("hsv_v", config.hsv_v)?;
        locals.set_item("translate", config.translate)?;
        locals.set_item("scale", config.scale)?;
        locals.set_item("shear", config.shear)?;
        locals.set_item("flipud", config.flipud)?;
        locals.set_item("fliplr", config.fliplr)?;
        locals.set_item("degrees", config.degrees)?;
        locals.set_item("workers", config.workers)?;
        locals.set_item("amp", config.amp)?;
        locals.set_item("resume", config.resume)?;
        locals.set_item("cls_pw", config.cls_pw)?;
        locals.set_item("stop_file", stop_file.to_string_lossy().as_ref())?;
        locals.set_item("log_path", log_path.to_string_lossy().as_ref())?;
        py.run_bound(TRAINING_CODE, Some(&locals), Some(&locals))?;
        Ok(())
    })
    .map_err(|error| {
        let formatted = format_python_error(error);
        append_log_line(log_path, &formatted);
        formatted
    })
}

fn configure_python_runtime(python_path: &str) -> Result<(), String> {
    let paths = PythonRuntimePaths::from_executable(python_path)?;
    let runtime_key = path_key(&paths.python_home);
    {
        let mut active_home = PYTHON_RUNTIME_HOME.lock().unwrap();
        if let Some(existing) = active_home.as_ref() {
            if existing != &runtime_key {
                return Err(format!(
                    "PyO3 Python runtime is already initialized with {}. Restart the app before switching to {}.",
                    existing,
                    paths.python_home.display()
                ));
            }
        } else {
            if python_is_initialized() {
                return Err(
                    "Python runtime was initialized before the configured Python path was applied. Restart the app and start training again."
                        .to_string(),
                );
            }
            apply_python_environment(&paths);
            pyo3::prepare_freethreaded_python();
            *active_home = Some(runtime_key);
        }
    }
    Ok(())
}

#[derive(Debug)]
struct PythonRuntimePaths {
    executable: PathBuf,
    python_home: PathBuf,
    extra_python_paths: Vec<PathBuf>,
    path_prefixes: Vec<PathBuf>,
}

impl PythonRuntimePaths {
    fn from_executable(python_path: &str) -> Result<Self, String> {
        let executable = PathBuf::from(python_path);
        let executable_dir = executable
            .parent()
            .ok_or_else(|| format!("Invalid Python path: {python_path}"))?
            .to_path_buf();
        let env_root = if file_name_eq(&executable_dir, "Scripts") {
            executable_dir
                .parent()
                .ok_or_else(|| format!("Invalid Python environment: {python_path}"))?
                .to_path_buf()
        } else {
            executable_dir.clone()
        };

        let python_home = resolve_python_home(&env_root)?;
        let mut extra_python_paths = vec![
            python_home.join("Lib"),
            python_home.join("DLLs"),
            python_home.join("Lib").join("site-packages"),
            env_root.join("DLLs"),
            env_root.join("Lib").join("site-packages"),
        ];
        extra_python_paths.retain(|path| path.exists());
        extra_python_paths = dedupe_pathbufs(extra_python_paths);

        let mut path_prefixes = vec![
            executable_dir,
            env_root.clone(),
            env_root.join("Scripts"),
            env_root.join("Library").join("bin"),
            env_root.join("DLLs"),
            python_home.clone(),
            python_home.join("DLLs"),
        ];
        path_prefixes.retain(|path| path.exists());
        path_prefixes = dedupe_pathbufs(path_prefixes);

        Ok(Self {
            executable,
            python_home,
            extra_python_paths,
            path_prefixes,
        })
    }
}

fn resolve_python_home(env_root: &Path) -> Result<PathBuf, String> {
    if has_python_encodings(env_root) {
        return Ok(normalize_path(env_root));
    }

    let pyvenv_cfg = env_root.join("pyvenv.cfg");
    if pyvenv_cfg.exists() {
        if let Ok(contents) = fs::read_to_string(&pyvenv_cfg) {
            for line in contents.lines() {
                let trimmed = line.trim();
                let Some((key, value)) = trimmed.split_once('=') else {
                    continue;
                };
                if key.trim().eq_ignore_ascii_case("home") {
                    let home = PathBuf::from(value.trim());
                    if has_python_encodings(&home) {
                        return Ok(normalize_path(&home));
                    }
                }
            }
        }
    }

    Err(format!(
        "Python standard library was not found under {}. Expected Lib\\encodings. Choose a full Python/Conda environment or python.exe.",
        env_root.display()
    ))
}

fn apply_python_environment(paths: &PythonRuntimePaths) {
    env::set_var("PYTHONHOME", paths.python_home.as_os_str());
    if let Ok(joined) = env::join_paths(&paths.extra_python_paths) {
        env::set_var("PYTHONPATH", joined);
    }

    let mut path_values = paths.path_prefixes.clone();
    if let Some(existing_path) = env::var_os("PATH") {
        path_values.extend(env::split_paths(&existing_path));
    }
    if let Ok(joined) = env::join_paths(dedupe_pathbufs(path_values)) {
        env::set_var("PATH", joined);
    }
    env::set_var("PYTHONNOUSERSITE", "1");
    env::set_var("PYTHONUTF8", "1");
    env::set_var("ULTRALYTICS_TQDM", "false");
    env::set_var("RUSTLABEL_PYTHON_EXE", paths.executable.as_os_str());
}

fn has_python_encodings(path: &Path) -> bool {
    path.join("Lib").join("encodings").is_dir()
}

fn python_is_initialized() -> bool {
    unsafe { pyo3::ffi::Py_IsInitialized() != 0 }
}

fn format_python_error(error: PyErr) -> String {
    Python::with_gil(|py| {
        if let Ok(traceback) = py.import_bound("traceback") {
            if let Ok(lines) = traceback
                .call_method1(
                    "format_exception",
                    (
                        error.get_type_bound(py),
                        error.value_bound(py),
                        error.traceback_bound(py),
                    ),
                )
                .and_then(|value| value.extract::<Vec<String>>())
            {
                let joined = lines.join("");
                if !joined.trim().is_empty() {
                    return joined;
                }
            }
        }
        let value = error.value_bound(py);
        value
            .str()
            .map(|text| text.to_string_lossy().into_owned())
            .unwrap_or_else(|_| error.to_string())
    })
}

fn verify_python_path(path: &str) -> Result<String, String> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Err("Python path is not configured. Set it in Settings.".to_string());
    }
    let python = PathBuf::from(trimmed);
    if !python.exists() {
        return Err(format!("Python not found at: {trimmed}"));
    }
    if python.is_file() {
        return Ok(python.to_string_lossy().into_owned());
    }

    let candidates = [
        python.join("python.exe"),
        python.join("Scripts").join("python.exe"),
        python.join(".venv").join("Scripts").join("python.exe"),
        python.join("venv").join("Scripts").join("python.exe"),
    ];
    for candidate in candidates {
        if candidate.is_file() {
            return Ok(candidate.to_string_lossy().into_owned());
        }
    }
    Err(format!(
        "Python executable was not found under: {}",
        python.display()
    ))
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
}

fn training_log_path() -> Result<PathBuf, String> {
    let directory = project_directory()?.join("logs");
    fs::create_dir_all(&directory)
        .map_err(|error| format!("create logs dir {}: {error}", directory.display()))?;
    Ok(directory.join(format!("{}.log", local_log_date_string())))
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

fn normalize_path(path: &Path) -> PathBuf {
    fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf())
}

fn path_key(path: &Path) -> String {
    normalize_path(path)
        .to_string_lossy()
        .replace('/', "\\")
        .to_lowercase()
}

fn dedupe_pathbufs(paths: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut seen = Vec::<String>::new();
    let mut result = Vec::new();
    for path in paths {
        let key = path_key(&path);
        if seen.iter().any(|value| value == &key) {
            continue;
        }
        seen.push(key);
        result.push(path);
    }
    result
}
