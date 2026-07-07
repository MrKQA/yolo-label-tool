use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
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
static ACTIVE_CHILD_PID: Lazy<Mutex<Option<u32>>> = Lazy::new(|| Mutex::new(None));

const TRAINING_SUBPROCESS_CODE: &str = r#"
import os
import sys

_rustlabel_dll_handles = []

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

def _rustlabel_configure_environment():
    python_exe_dir = os.path.dirname(python_path)
    python_root = python_exe_dir
    if os.path.basename(python_exe_dir).lower() == "scripts":
        python_root = os.path.dirname(python_exe_dir)
    worker_python_path = python_path
    if os.name == "nt":
        pythonw_path = os.path.join(python_exe_dir, "pythonw.exe")
        if os.path.isfile(pythonw_path):
            worker_python_path = pythonw_path

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
    os.environ["NO_COLOR"] = "1"
    os.environ["PY_COLORS"] = "0"
    os.environ["CLICOLOR"] = "0"
    os.environ["CLICOLOR_FORCE"] = "0"
    os.environ["FORCE_COLOR"] = "0"
    os.environ["RICH_NO_COLOR"] = "1"
    os.environ["TERM"] = "dumb"
    os.environ.pop("ULTRALYTICS_TQDM", None)
    os.environ["CONDA_PREFIX"] = python_root
    os.environ["CONDA_DLL_SEARCH_MODIFICATION_ENABLE"] = "1"

    if hasattr(os, "add_dll_directory"):
        for item in path_candidates:
            if item and os.path.isdir(item):
                try:
                    _rustlabel_dll_handles.append(os.add_dll_directory(item))
                except Exception as error:
                    print(f"[rustlabel] add_dll_directory failed: {item}: {error}", flush=True)

    return python_exe_dir, python_root, worker_python_path

def _rustlabel_configure_multiprocessing(worker_python_path):
    try:
        import multiprocessing as _rustlabel_multiprocessing
        import multiprocessing.spawn as _rustlabel_multiprocessing_spawn
        sys.executable = worker_python_path
        if hasattr(sys, "_base_executable"):
            sys._base_executable = worker_python_path
        _rustlabel_multiprocessing.freeze_support()
        _rustlabel_multiprocessing.set_executable(worker_python_path)
        print(
            f"[rustlabel] multiprocessing executable={_rustlabel_multiprocessing_spawn.get_executable()}",
            flush=True,
        )
    except Exception as error:
        print(f"[rustlabel] configure multiprocessing executable failed: {error}", flush=True)

def _rustlabel_main():
    python_exe_dir, python_root, worker_python_path = _rustlabel_configure_environment()
    _rustlabel_configure_multiprocessing(worker_python_path)

    print("[rustlabel] Python training subprocess bootstrap", flush=True)
    print(f"[rustlabel] python_path={python_path}", flush=True)
    print(f"[rustlabel] worker_python_path={worker_python_path}", flush=True)
    print(f"[rustlabel] python_root={python_root}", flush=True)
    print(f"[rustlabel] model_path={model_path}", flush=True)
    print(f"[rustlabel] data_yaml_path={data_yaml_path}", flush=True)
    print(f"[rustlabel] project_dir={project_dir}", flush=True)
    print(f"[rustlabel] experiment_name={experiment_name}", flush=True)
    print(
        f"[rustlabel] epochs={epochs}, imgsz={imgsz}, batch={batch}, "
        f"device={device}, workers={workers}, amp={amp}, resume={resume}",
        flush=True,
    )

    print("[rustlabel] importing ultralytics.YOLO", flush=True)
    from ultralytics import YOLO
    print("[rustlabel] ultralytics import complete", flush=True)

    print("[rustlabel] loading model", flush=True)
    model = YOLO(model_path)
    print("[rustlabel] model loaded", flush=True)
    try:
        model.add_callback("on_train_start", _rustlabel_stop_callback)
        model.add_callback("on_train_epoch_start", _rustlabel_stop_callback)
        model.add_callback("on_train_batch_start", _rustlabel_stop_callback)
        model.add_callback("on_train_batch_end", _rustlabel_stop_callback)
        model.add_callback("on_train_epoch_end", _rustlabel_stop_callback)
        model.add_callback("on_fit_epoch_end", _rustlabel_stop_callback)
    except Exception as error:
        print(f"[rustlabel] register stop callback failed: {error}", flush=True)

    if cls_pw > 0 and hasattr(model, "cls_pw"):
        model.cls_pw = cls_pw

    if resume:
        print("[rustlabel] calling model.train(resume=True)", flush=True)
        model.train(resume=True)
    else:
        print("[rustlabel] calling model.train(...)", flush=True)
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
            verbose=True,
            project=project_dir,
            name=experiment_name,
            exist_ok=True,
        )
    print("[rustlabel] training call finished", flush=True)

if __name__ == "__main__":
    _rustlabel_main()
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
    let python_path = ini_python::verify_python_path(python_path)?;
    let log_path = training_log_path().ok();
    if let Some(path) = &log_path {
        append_log_line(
            path,
            &format!("python executable verified without preload: {python_path}"),
        );
    }
    Ok("Python executable verified without YOLO preload".to_string())
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

pub fn shutdown_training(timeout_ms: u64) -> Result<String, String> {
    let message = stop_training()?;
    let deadline = Instant::now() + Duration::from_millis(timeout_ms);
    let mut kill_requested = false;
    loop {
        cleanup_finished_training();
        if ACTIVE_HANDLE.lock().unwrap().is_none() {
            return Ok(format!("{message}; training stopped"));
        }
        if Instant::now() >= deadline {
            if !kill_requested {
                if let Some(log_path) = ACTIVE_LOG_PATH.lock().unwrap().clone() {
                    append_log_line(
                        Path::new(&log_path),
                        "training stop timed out; killing subprocess",
                    );
                }
                kill_active_training_child();
                kill_requested = true;
                thread::sleep(Duration::from_millis(200));
                continue;
            }
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
    Ok((
        path.to_string_lossy().into_owned(),
        sanitize_terminal_text(&tail),
    ))
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
    let text = sanitize_terminal_text(&text);
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
    append_log_line(log_path, "training subprocess prepare starting");
    run_training_subprocess(config, stop_file, log_path)
}

fn run_training_subprocess(
    config: &TrainingConfig,
    stop_file: &Path,
    log_path: &Path,
) -> Result<(), String> {
    let script_path = training_script_path()?;
    let code = training_code_with_locals(config, stop_file, log_path);
    fs::write(&script_path, code)
        .map_err(|error| format!("write training script {}: {error}", script_path.display()))?;
    append_log_line(
        log_path,
        &format!("training subprocess script={}", script_path.display()),
    );

    let mut command = Command::new(&config.python_path);
    command
        .arg("-u")
        .arg(&script_path)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    configure_python_child_environment(&mut command, &config.python_path);

    let mut child = command
        .spawn()
        .map_err(|error| format!("start training subprocess: {error}"))?;
    let child_id = child.id();
    *ACTIVE_CHILD_PID.lock().unwrap() = Some(child_id);
    append_log_line(log_path, &format!("training subprocess pid={child_id}"));

    let log_write_lock = Arc::new(Mutex::new(()));
    let stdout_handle = child.stdout.take().map(|pipe| {
        spawn_child_output_logger(pipe, log_path.to_path_buf(), log_write_lock.clone())
    });
    let stderr_handle = child.stderr.take().map(|pipe| {
        spawn_child_output_logger(pipe, log_path.to_path_buf(), log_write_lock.clone())
    });

    let wait_result = child
        .wait()
        .map_err(|error| format!("wait training subprocess: {error}"));
    if let Some(handle) = stdout_handle {
        let _ = handle.join();
    }
    if let Some(handle) = stderr_handle {
        let _ = handle.join();
    }
    *ACTIVE_CHILD_PID.lock().unwrap() = None;
    let _ = fs::remove_file(&script_path);

    let status = wait_result?;
    if status.success() {
        append_log_line(log_path, "training subprocess exited successfully");
        return Ok(());
    }
    if stop_file.exists() {
        append_log_line(
            log_path,
            &format!("training subprocess stopped with status={status}"),
        );
        return Err("KeyboardInterrupt: Training stopped by RustLabel".to_string());
    }
    append_log_line(
        log_path,
        &format!("training subprocess failed with status={status}"),
    );
    Err(format!("training subprocess failed: {status}"))
}

fn spawn_child_output_logger<R>(
    mut reader: R,
    log_path: PathBuf,
    write_lock: Arc<Mutex<()>>,
) -> JoinHandle<()>
where
    R: Read + Send + 'static,
{
    thread::spawn(move || {
        let mut buffer = [0_u8; 8192];
        loop {
            match reader.read(&mut buffer) {
                Ok(0) => break,
                Ok(count) => append_log_bytes(&log_path, &buffer[..count], &write_lock),
                Err(_) => break,
            }
        }
    })
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
        TRAINING_SUBPROCESS_CODE
    )
}

fn training_script_path() -> Result<PathBuf, String> {
    let path = env::temp_dir().join(format!(
        "_rustlabel_train_{}_{}.py",
        std::process::id(),
        unix_millis_now().unwrap_or(0)
    ));
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("create temp script dir {}: {error}", parent.display()))?;
    }
    Ok(path)
}

fn configure_python_child_environment(command: &mut Command, python_path: &str) {
    let executable = PathBuf::from(python_path);
    let executable_dir = executable.parent().map(Path::to_path_buf);
    let env_root = executable_dir
        .as_ref()
        .and_then(|dir| {
            if file_name_eq(dir, "Scripts") {
                dir.parent().map(Path::to_path_buf)
            } else {
                Some(dir.clone())
            }
        })
        .unwrap_or_else(|| PathBuf::from("."));

    let mut path_prefixes = Vec::<PathBuf>::new();
    if let Some(dir) = executable_dir {
        path_prefixes.push(dir);
    }
    path_prefixes.extend([
        env_root.clone(),
        env_root.join("Scripts"),
        env_root.join("Library").join("bin"),
        env_root.join("DLLs"),
    ]);
    path_prefixes.retain(|path| path.exists());
    if let Some(existing_path) = env::var_os("PATH") {
        path_prefixes.extend(env::split_paths(&existing_path));
    }
    if let Ok(joined) = env::join_paths(dedupe_pathbufs(path_prefixes)) {
        command.env("PATH", joined);
    }

    command
        .env_remove("PYTHONHOME")
        .env_remove("PYTHONPATH")
        .env_remove("ULTRALYTICS_TQDM")
        .env("PYTHONNOUSERSITE", "1")
        .env("PYTHONUTF8", "1")
        .env("NO_COLOR", "1")
        .env("PY_COLORS", "0")
        .env("CLICOLOR", "0")
        .env("CLICOLOR_FORCE", "0")
        .env("FORCE_COLOR", "0")
        .env("RICH_NO_COLOR", "1")
        .env("TERM", "dumb")
        .env("CONDA_PREFIX", &env_root)
        .env("CONDA_DLL_SEARCH_MODIFICATION_ENABLE", "1")
        .env("RUSTLABEL_PYTHON_EXE", python_path);
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
    *ACTIVE_CHILD_PID.lock().unwrap() = None;
    *ACTIVE_STARTED_AT.lock().unwrap() = None;
}

fn kill_active_training_child() {
    let pid = *ACTIVE_CHILD_PID.lock().unwrap();
    let Some(pid) = pid else {
        return;
    };
    #[cfg(windows)]
    {
        let pid_text = pid.to_string();
        let _ = Command::new("taskkill")
            .args(["/PID", pid_text.as_str(), "/T", "/F"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
    #[cfg(not(windows))]
    {
        let pid_text = pid.to_string();
        let _ = Command::new("kill")
            .args(["-TERM", pid_text.as_str()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
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

fn append_log_bytes(path: &Path, bytes: &[u8], write_lock: &Arc<Mutex<()>>) {
    if bytes.is_empty() {
        return;
    }
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
    let Ok(_guard) = write_lock.lock() else {
        return;
    };
    if let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = file.write_all(bytes);
        let _ = file.flush();
    }
}

fn sanitize_terminal_text(input: &str) -> String {
    enum EscapeState {
        Normal,
        Escape,
        Csi,
        Osc,
        OscEscape,
    }

    let mut output = String::with_capacity(input.len());
    let mut state = EscapeState::Normal;
    for ch in input.chars() {
        match state {
            EscapeState::Normal => match ch {
                '\u{1b}' => state = EscapeState::Escape,
                '\r' => {
                    if !output.ends_with('\n') {
                        output.push('\n');
                    }
                }
                '\u{8}' => {}
                _ => output.push(ch),
            },
            EscapeState::Escape => {
                state = match ch {
                    '[' => EscapeState::Csi,
                    ']' => EscapeState::Osc,
                    _ => EscapeState::Normal,
                };
            }
            EscapeState::Csi => {
                if ('@'..='~').contains(&ch) {
                    state = EscapeState::Normal;
                }
            }
            EscapeState::Osc => {
                if ch == '\u{7}' {
                    state = EscapeState::Normal;
                } else if ch == '\u{1b}' {
                    state = EscapeState::OscEscape;
                }
            }
            EscapeState::OscEscape => {
                state = if ch == '\\' {
                    EscapeState::Normal
                } else {
                    EscapeState::Osc
                };
            }
        }
    }
    output
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

fn dedupe_pathbufs(paths: Vec<PathBuf>) -> Vec<PathBuf> {
    let mut result = Vec::<PathBuf>::new();
    for path in paths {
        if !result.iter().any(|existing| {
            existing
                .to_string_lossy()
                .eq_ignore_ascii_case(&path.to_string_lossy())
        }) {
            result.push(path);
        }
    }
    result
}
