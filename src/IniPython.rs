use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use once_cell::sync::Lazy;
use pyo3::prelude::*;

static PYTHON_RUNTIME_HOME: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));

pub fn initialize_python(python_path: &str) -> Result<String, String> {
    let verified = verify_python_path(python_path)?;
    configure_python_runtime(&verified)?;
    Ok(verified)
}

pub fn verify_python_path(path: &str) -> Result<String, String> {
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

pub fn configure_python_runtime(python_path: &str) -> Result<(), String> {
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

pub fn preload_yolo_modules() -> Result<(), String> {
    Python::with_gil(|py| -> PyResult<()> {
        py.run_bound(
            r#"
import builtins
import os
import sys
os.environ["ULTRALYTICS_TQDM"] = "false"
os.environ["YOLO_VERBOSE"] = "false"
if not hasattr(builtins, "_rustlabel_dll_handles"):
    builtins._rustlabel_dll_handles = []
if hasattr(os, "add_dll_directory"):
    for item in os.environ.get("PATH", "").split(os.pathsep):
        if item and os.path.isdir(item):
            try:
                builtins._rustlabel_dll_handles.append(os.add_dll_directory(item))
            except Exception:
                pass
import torch
from ultralytics import YOLO
"#,
            None,
            None,
        )?;
        Ok(())
    })
    .map_err(|error| error.to_string())
}

pub fn shutdown_python_runtime() -> Result<(), String> {
    if !python_is_initialized() {
        return Ok(());
    }
    Python::with_gil(|py| -> PyResult<()> {
        py.run_bound(
            r#"
try:
    import multiprocessing
    for child in multiprocessing.active_children():
        try:
            child.terminate()
        except Exception:
            pass
        try:
            child.join(timeout=1.0)
        except Exception:
            pass
        if getattr(child, "is_alive", lambda: False)():
            try:
                child.kill()
            except Exception:
                pass
except Exception:
    pass
try:
    import torch
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
except Exception:
    pass
"#,
            None,
            None,
        )?;
        Ok(())
    })
    .map_err(|error| error.to_string())
}

pub fn format_python_error(error: PyErr) -> String {
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
