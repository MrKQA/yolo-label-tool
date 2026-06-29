use std::env;
use std::ffi::{c_char, c_int, c_void, CString};
use std::fs;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use once_cell::sync::Lazy;

static PYTHON_RUNTIME: Lazy<Mutex<Option<PythonRuntime>>> = Lazy::new(|| Mutex::new(None));

type PyInitializeEx = unsafe extern "C" fn(c_int);
type PyIsInitialized = unsafe extern "C" fn() -> c_int;
type PyRunSimpleStringFlags = unsafe extern "C" fn(*const c_char, *mut c_void) -> c_int;
type PyEvalSaveThread = unsafe extern "C" fn() -> *mut c_void;
type PyGilStateEnsure = unsafe extern "C" fn() -> c_int;
type PyGilStateRelease = unsafe extern "C" fn(c_int);

struct PythonRuntime {
    home_key: String,
    dll_path: PathBuf,
    _module: usize,
    py_initialize_ex: PyInitializeEx,
    py_is_initialized: PyIsInitialized,
    py_run_simple_string_flags: PyRunSimpleStringFlags,
    py_eval_save_thread: PyEvalSaveThread,
    py_gil_state_ensure: PyGilStateEnsure,
    py_gil_state_release: PyGilStateRelease,
}

unsafe impl Send for PythonRuntime {}

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
    let mut active = PYTHON_RUNTIME.lock().unwrap();
    if let Some(runtime) = active.as_ref() {
        if runtime.home_key == runtime_key {
            return Ok(());
        }
        return Err(format!(
            "Python runtime is already initialized with {}. Restart the app before switching to {}.",
            runtime.home_key,
            paths.python_home.display()
        ));
    }

    apply_python_environment(&paths);
    let dll_path = find_python_dll(&paths)?;
    let runtime = load_python_runtime(&dll_path, runtime_key)?;
    let initialized_here = unsafe {
        let initialized_here = (runtime.py_is_initialized)() == 0;
        if (runtime.py_is_initialized)() == 0 {
            (runtime.py_initialize_ex)(0);
        }
        if (runtime.py_is_initialized)() == 0 {
            return Err(format!(
                "Python initialization failed: {}",
                dll_path.display()
            ));
        }
        initialized_here
    };
    if initialized_here {
        unsafe {
            (runtime.py_eval_save_thread)();
        }
    }
    run_python_code_with_runtime(&runtime, "import sys\n")?;
    *active = Some(runtime);
    Ok(())
}

pub fn preload_yolo_modules() -> Result<(), String> {
    run_python_code(
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
try:
    import onnxruntime
except Exception as error:
    print(f"import onnxruntime error....... {error}")
    python_exe = os.environ.get("RUSTLABEL_PYTHON_EXE") or sys.executable
    os.system(f'"{python_exe}" -m pip install onnxruntime-gpu')
    import onnxruntime
from ultralytics import YOLO
"#,
    )
}

pub fn shutdown_python_runtime() -> Result<(), String> {
    if !python_is_initialized() {
        return Ok(());
    }
    run_python_code(
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
    )
}

pub fn run_python_code(code: &str) -> Result<(), String> {
    let active = PYTHON_RUNTIME.lock().unwrap();
    let runtime = active
        .as_ref()
        .ok_or_else(|| "Python runtime is not initialized.".to_string())?;
    run_python_code_with_runtime(runtime, code)
}

pub fn python_is_initialized() -> bool {
    let active = PYTHON_RUNTIME.lock().unwrap();
    let Some(runtime) = active.as_ref() else {
        return false;
    };
    unsafe { (runtime.py_is_initialized)() != 0 }
}

fn run_python_code_with_runtime(runtime: &PythonRuntime, code: &str) -> Result<(), String> {
    let error_path = env::temp_dir().join(format!(
        "rustlabel_python_error_{}_{}.txt",
        std::process::id(),
        unix_millis_now()
    ));
    let wrapped = wrap_python_code_for_traceback(code, &error_path);
    let code = CString::new(wrapped).map_err(|_| "Python code contains NUL byte".to_string())?;
    let result = unsafe {
        let gil = (runtime.py_gil_state_ensure)();
        let result = (runtime.py_run_simple_string_flags)(code.as_ptr(), ptr::null_mut());
        (runtime.py_gil_state_release)(gil);
        result
    };
    if result == 0 {
        let _ = fs::remove_file(&error_path);
        Ok(())
    } else {
        let details = fs::read_to_string(&error_path).unwrap_or_default();
        let _ = fs::remove_file(&error_path);
        let details = details.trim();
        if details.is_empty() {
            Err(format!(
                "Python code execution failed in {}. See the training terminal/log output for details.",
                runtime.dll_path.display()
            ))
        } else {
            Err(format!(
                "Python code execution failed in {}.\n{}",
                runtime.dll_path.display(),
                details
            ))
        }
    }
}

fn wrap_python_code_for_traceback(code: &str, error_path: &Path) -> String {
    format!(
        r#"import sys, traceback
try:
    exec({})
except BaseException:
    _rustlabel_traceback = traceback.format_exc()
    try:
        with open({}, "w", encoding="utf-8") as _rustlabel_file:
            _rustlabel_file.write(_rustlabel_traceback)
    except Exception:
        pass
    sys.stderr.write(_rustlabel_traceback)
    raise
"#,
        python_string_literal(code),
        python_string_literal(&error_path.to_string_lossy())
    )
}

fn python_string_literal(value: &str) -> String {
    let mut result = String::with_capacity(value.len() + 2);
    result.push('\'');
    for ch in value.chars() {
        match ch {
            '\\' => result.push_str("\\\\"),
            '\'' => result.push_str("\\'"),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            ch if ch.is_control() => result.push_str(&format!("\\u{:04x}", ch as u32)),
            ch => result.push(ch),
        }
    }
    result.push('\'');
    result
}

#[derive(Debug)]
struct PythonRuntimePaths {
    executable: PathBuf,
    python_home: PathBuf,
    env_root: PathBuf,
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
            env_root,
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

fn find_python_dll(paths: &PythonRuntimePaths) -> Result<PathBuf, String> {
    let mut candidates = Vec::<PathBuf>::new();
    for directory in dedupe_pathbufs(vec![
        paths
            .executable
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| paths.env_root.clone()),
        paths.env_root.clone(),
        paths.python_home.clone(),
        paths.env_root.join("DLLs"),
        paths.python_home.join("DLLs"),
    ]) {
        if !directory.is_dir() {
            continue;
        }
        let Ok(entries) = fs::read_dir(&directory) else {
            continue;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
                continue;
            };
            if python_dll_score(name).is_some() {
                candidates.push(path);
            }
        }
    }
    candidates.sort_by(|a, b| {
        let a_name = a.file_name().and_then(|value| value.to_str()).unwrap_or("");
        let b_name = b.file_name().and_then(|value| value.to_str()).unwrap_or("");
        python_dll_score(a_name)
            .unwrap_or(99)
            .cmp(&python_dll_score(b_name).unwrap_or(99))
            .then_with(|| a_name.cmp(b_name))
    });
    candidates.into_iter().next().ok_or_else(|| {
        format!(
            "Python DLL was not found near {}. Expected pythonXY.dll or python3.dll.",
            paths.executable.display()
        )
    })
}

fn python_dll_score(name: &str) -> Option<u8> {
    let lower = name.to_ascii_lowercase();
    if !lower.starts_with("python") || !lower.ends_with(".dll") {
        return None;
    }
    let stem = lower.trim_end_matches(".dll");
    let suffix = stem.trim_start_matches("python");
    if suffix.len() >= 2 && suffix.chars().all(|ch| ch.is_ascii_digit()) {
        return Some(0);
    }
    if stem == "python3" {
        return Some(1);
    }
    Some(2)
}

fn load_python_runtime(dll_path: &Path, home_key: String) -> Result<PythonRuntime, String> {
    let module = load_library(dll_path)?;
    let runtime = unsafe {
        PythonRuntime {
            home_key,
            dll_path: dll_path.to_path_buf(),
            _module: module,
            py_initialize_ex: load_symbol(module, "Py_InitializeEx")?,
            py_is_initialized: load_symbol(module, "Py_IsInitialized")?,
            py_run_simple_string_flags: load_symbol(module, "PyRun_SimpleStringFlags")?,
            py_eval_save_thread: load_symbol(module, "PyEval_SaveThread")?,
            py_gil_state_ensure: load_symbol(module, "PyGILState_Ensure")?,
            py_gil_state_release: load_symbol(module, "PyGILState_Release")?,
        }
    };
    Ok(runtime)
}

#[cfg(windows)]
fn load_library(path: &Path) -> Result<usize, String> {
    use std::os::windows::ffi::OsStrExt;

    const LOAD_WITH_ALTERED_SEARCH_PATH: u32 = 0x00000008;

    extern "system" {
        fn LoadLibraryExW(
            lp_lib_file_name: *const u16,
            h_file: *mut c_void,
            dw_flags: u32,
        ) -> *mut c_void;
    }

    let wide: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
    let handle = unsafe {
        LoadLibraryExW(
            wide.as_ptr(),
            ptr::null_mut(),
            LOAD_WITH_ALTERED_SEARCH_PATH,
        )
    };
    if handle.is_null() {
        return Err(format!("LoadLibraryExW failed: {}", path.display()));
    }
    Ok(handle as usize)
}

#[cfg(not(windows))]
fn load_library(_path: &Path) -> Result<usize, String> {
    Err("Dynamic Python loading is currently implemented for Windows.".to_string())
}

#[cfg(windows)]
unsafe fn load_symbol<T: Copy>(module: usize, name: &str) -> Result<T, String> {
    extern "system" {
        fn GetProcAddress(h_module: *mut c_void, lp_proc_name: *const c_char) -> *mut c_void;
    }

    let name_c = CString::new(name).map_err(|_| format!("Invalid symbol name: {name}"))?;
    let pointer = GetProcAddress(module as *mut c_void, name_c.as_ptr());
    if pointer.is_null() {
        return Err(format!("Python symbol was not found: {name}"));
    }
    Ok(std::mem::transmute_copy(&pointer))
}

#[cfg(not(windows))]
unsafe fn load_symbol<T: Copy>(_module: usize, name: &str) -> Result<T, String> {
    Err(format!("Python symbol was not found: {name}"))
}

fn has_python_encodings(path: &Path) -> bool {
    path.join("Lib").join("encodings").is_dir()
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

fn unix_millis_now() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
}
