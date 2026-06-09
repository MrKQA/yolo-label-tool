use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

use once_cell::sync::Lazy;

#[cfg(windows)]
use std::os::windows::process::CommandExt;

static DETECT_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x08000000;

#[derive(Debug, Clone)]
pub struct DetectImageRequest {
    pub python_path: String,
    pub model_path: String,
    pub input_path: String,
    pub output_dir: String,
    pub output_name: String,
    pub conf_threshold: f64,
    pub iou_threshold: f64,
    pub imgsz: u32,
    pub device: String,
}

#[derive(Debug, Clone)]
pub struct DetectVideoRequest {
    pub python_path: String,
    pub model_path: String,
    pub input_path: String,
    pub output_dir: String,
    pub output_name: String,
    pub conf_threshold: f64,
    pub iou_threshold: f64,
    pub imgsz: u32,
    pub device: String,
    pub ffmpeg_path: String,
    pub preview_frames: bool,
    pub cancel_path: String,
    pub start_frame: u32,
}

#[derive(Debug, Clone)]
pub struct DetectResult {
    pub ok: bool,
    pub output_path: String,
    pub error: Option<String>,
    pub label_count: u32,
}

#[derive(Debug, Clone)]
pub struct DetectModelTaskResult {
    pub ok: bool,
    pub task: String,
    pub folder: String,
    pub error: Option<String>,
}

pub fn detect_model_task(python_path: &str, model_path: &str) -> DetectModelTaskResult {
    let python = verify_python(python_path);
    if let Err(e) = python {
        return DetectModelTaskResult {
            ok: false,
            task: String::new(),
            folder: "hbb".to_string(),
            error: Some(e),
        };
    }
    let python = python.unwrap();
    let script = format!(
        r##"import json, os
os.environ["ULTRALYTICS_TQDM"] = "false"
os.environ["YOLO_VERBOSE"] = "false"
from ultralytics import YOLO
model = YOLO(r'{model_path}')
task = str(getattr(model, "task", "") or "detect")
print(json.dumps({{"ok": True, "task": task}}))
"##,
        model_path = model_path.replace('\\', "\\\\"),
    );
    match run_python_script(&python, &script, None) {
        Ok(stdout) => {
            let task = parse_json_string(&stdout, "task").unwrap_or_else(|| "detect".to_string());
            DetectModelTaskResult {
                ok: true,
                folder: model_task_to_folder(&task),
                task,
                error: None,
            }
        }
        Err(e) => DetectModelTaskResult {
            ok: false,
            task: String::new(),
            folder: "hbb".to_string(),
            error: Some(e),
        },
    }
}

pub fn detect_image(req: &DetectImageRequest) -> DetectResult {
    let _guard = DETECT_LOCK.lock().unwrap();
    let output_dir = PathBuf::from(&req.output_dir);
    let _ = fs::create_dir_all(&output_dir);
    let output_path = output_dir.join(&req.output_name);

    let python = verify_python(&req.python_path);
    if let Err(e) = python {
        return DetectResult {
            ok: false,
            output_path: String::new(),
            error: Some(e),
            label_count: 0,
        };
    }
    let python = python.unwrap();

    let script = format!(
        r##"import sys, json, os
os.environ["ULTRALYTICS_TQDM"] = "false"
os.environ["YOLO_VERBOSE"] = "false"
from ultralytics import YOLO
model = YOLO(r'{model_path}')
device_value = r'{device}'.strip()
if device_value.lower() in ("", "auto", "cuda", "nv", "nvidia"):
    try:
        import torch
        device_value = "0" if torch.cuda.is_available() and torch.cuda.device_count() > 0 else "cpu"
    except Exception:
        device_value = "cpu"

def _rustlabel_predict(source):
    global device_value
    try:
        return model.predict(source, save=False, imgsz={imgsz},
            conf={conf}, iou={iou}, device=device_value, verbose=False, stream=False)
    except Exception as error:
        if str(device_value).lower() != "cpu":
            print(f"[rustlabel] CUDA predict failed, fallback to CPU: {{error}}", file=sys.stderr)
            device_value = "cpu"
            return model.predict(source, save=False, imgsz={imgsz},
                conf={conf}, iou={iou}, device=device_value, verbose=False, stream=False)
        raise

results = _rustlabel_predict(r'{input_path}')
import cv2, numpy as np
img = cv2.imread(r'{input_path}')
label_count = 0
for r in results:
    if r.boxes is not None:
        label_count = len(r.boxes)
    annotated = r.plot()
    cv2.imwrite(r'{output_path}', annotated)
print(json.dumps({{"ok": True, "label_count": label_count}}))
"##,
        model_path = req.model_path.replace('\\', "\\\\"),
        input_path = req.input_path.replace('\\', "\\\\"),
        output_path = output_path.to_string_lossy().replace('\\', "\\\\"),
        imgsz = req.imgsz,
        conf = req.conf_threshold,
        iou = req.iou_threshold,
        device = req.device,
    );

    match run_python_script(&python, &script, None) {
        Ok(stdout) => {
            let label_count = parse_label_count(&stdout);
            DetectResult {
                ok: true,
                output_path: output_path.to_string_lossy().into_owned(),
                error: None,
                label_count,
            }
        }
        Err(e) => DetectResult {
            ok: false,
            output_path: String::new(),
            error: Some(e),
            label_count: 0,
        },
    }
}

fn detect_video_frames(req: &DetectVideoRequest) -> DetectResult {
    let _guard = DETECT_LOCK.lock().unwrap();
    let output_dir = PathBuf::from(&req.output_dir);
    let _ = fs::create_dir_all(&output_dir);
    let output_path = output_dir.join(&req.output_name);
    let frame_dir_name = Path::new(&req.output_name)
        .file_stem()
        .and_then(|value| value.to_str())
        .map(|value| format!("{value}_frames"))
        .unwrap_or_else(|| "preview_frames".to_string());
    let frame_dir = output_dir.join(frame_dir_name);

    let python = verify_python(&req.python_path);
    if let Err(e) = python {
        return DetectResult {
            ok: false,
            output_path: String::new(),
            error: Some(e),
            label_count: 0,
        };
    }
    let python = python.unwrap();

    let script = format!(
        r##"import sys, json, os, shutil, time
os.environ["ULTRALYTICS_TQDM"] = "false"
os.environ["YOLO_VERBOSE"] = "false"
from ultralytics import YOLO
import cv2
model = YOLO(r'{model_path}')
cap = cv2.VideoCapture(r'{input_path}')
if not cap.isOpened():
    print(json.dumps({{"ok": False, "error": "Cannot open video"}}))
    sys.exit(1)
fps = cap.get(cv2.CAP_PROP_FPS)
if not fps or fps <= 0:
    fps = 25.0
total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
if width <= 0 or height <= 0:
    print(json.dumps({{"ok": False, "error": "Invalid video size"}}))
    sys.exit(1)
start_frame = int({start_frame})
if start_frame > 0:
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
device_value = r'{device}'.strip()
if device_value.lower() in ("", "auto", "cuda", "nv", "nvidia"):
    try:
        import torch
        device_value = "0" if torch.cuda.is_available() and torch.cuda.device_count() > 0 else "cpu"
    except Exception:
        device_value = "cpu"

def _rustlabel_predict(source):
    global device_value
    try:
        return model.predict(source, save=False, imgsz={imgsz},
            conf={conf}, iou={iou}, device=device_value, verbose=False, stream=True)
    except Exception as error:
        if str(device_value).lower() != "cpu":
            print(f"[rustlabel] CUDA predict failed, fallback to CPU: {{error}}", file=sys.stderr)
            device_value = "cpu"
            return model.predict(source, save=False, imgsz={imgsz},
                conf={conf}, iou={iou}, device=device_value, verbose=False, stream=True)
        raise

frame_dir = r'{frame_dir}'
manifest_path = r'{output_path}'
cancel_path = r'{cancel_path}'
shutil.rmtree(frame_dir, ignore_errors=True)
os.makedirs(frame_dir, exist_ok=True)
frames = []
frame_idx = 0
frame_number = start_frame
label_count = 0

def _write_manifest(complete=False, canceled=False):
    manifest = {{
        "ok": True,
        "type": "frames",
        "fps": fps,
        "width": width,
        "height": height,
        "totalFrames": total_frames,
        "startFrame": start_frame,
        "complete": complete,
        "canceled": canceled,
        "frames": frames,
    }}
    tmp_path = manifest_path + f".{{os.getpid()}}.tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False)
    last_error = None
    for _ in range(30):
        try:
            os.replace(tmp_path, manifest_path)
            return
        except PermissionError as error:
            last_error = error
            time.sleep(0.03)
    try:
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False)
    except PermissionError:
        raise last_error

_write_manifest(complete=False, canceled=False)
try:
    while True:
        if cancel_path and os.path.exists(cancel_path):
            break
        ret, frame = cap.read()
        if not ret:
            break
        results = _rustlabel_predict(frame)
        annotated = frame
        speed = {{}}
        for r in results:
            if r.boxes is not None:
                label_count = max(label_count, len(r.boxes))
            speed = getattr(r, "speed", {{}}) or {{}}
            annotated = r.plot()
        frame_path = os.path.join(frame_dir, f"frame_{{frame_idx:06d}}.png")
        cv2.imwrite(frame_path, annotated)
        frames.append({{
            "path": frame_path.replace("\\", "/"),
            "frameNumber": frame_number,
            "preprocessMs": float(speed.get("preprocess", 0.0) or 0.0),
            "inferenceMs": float(speed.get("inference", 0.0) or 0.0),
            "postprocessMs": float(speed.get("postprocess", 0.0) or 0.0),
        }})
        frame_idx += 1
        frame_number += 1
        _write_manifest(complete=False, canceled=False)
finally:
    cap.release()

was_canceled = bool(cancel_path and os.path.exists(cancel_path))
_write_manifest(complete=True, canceled=was_canceled)
print(json.dumps({{"ok": True, "frame_count": frame_idx, "fps": fps,
    "width": width, "height": height, "label_count": label_count}}))
"##,
        model_path = req.model_path.replace('\\', "\\\\"),
        input_path = req.input_path.replace('\\', "\\\\"),
        output_path = output_path.to_string_lossy().replace('\\', "\\\\"),
        frame_dir = frame_dir.to_string_lossy().replace('\\', "\\\\"),
        cancel_path = req.cancel_path.replace('\\', "\\\\"),
        start_frame = req.start_frame,
        imgsz = req.imgsz,
        conf = req.conf_threshold,
        iou = req.iou_threshold,
        device = req.device,
    );

    let stdout = match run_python_script(&python, &script, None) {
        Ok(s) => s,
        Err(e) => {
            return DetectResult {
                ok: false,
                output_path: String::new(),
                error: Some(e),
                label_count: 0,
            };
        }
    };

    let frame_count = parse_u32_field(&stdout, "frame_count").unwrap_or(0);
    let label_count = parse_u32_field(&stdout, "label_count").unwrap_or(0);

    if frame_count == 0 && req.cancel_path.trim().is_empty() {
        return DetectResult {
            ok: false,
            output_path: String::new(),
            error: Some("No frames extracted".into()),
            label_count: 0,
        };
    }

    DetectResult {
        ok: true,
        output_path: output_path.to_string_lossy().into_owned(),
        error: None,
        label_count,
    }
}

pub fn detect_video(req: &DetectVideoRequest) -> DetectResult {
    if req.preview_frames {
        return detect_video_frames(req);
    }

    let _guard = DETECT_LOCK.lock().unwrap();
    let output_dir = PathBuf::from(&req.output_dir);
    let _ = fs::create_dir_all(&output_dir);
    let output_path = output_dir.join(&req.output_name);

    let python = verify_python(&req.python_path);
    if let Err(e) = python {
        return DetectResult {
            ok: false,
            output_path: String::new(),
            error: Some(e),
            label_count: 0,
        };
    }
    let python = python.unwrap();

    let script = format!(
        r##"import sys, json, os, subprocess
os.environ["ULTRALYTICS_TQDM"] = "false"
os.environ["YOLO_VERBOSE"] = "false"
from ultralytics import YOLO
import cv2
import numpy as np
model = YOLO(r'{model_path}')
cap = cv2.VideoCapture(r'{input_path}')
if not cap.isOpened():
    print(json.dumps({{"ok": False, "error": "Cannot open video"}}))
    sys.exit(1)
fps = cap.get(cv2.CAP_PROP_FPS)
if not fps or fps <= 0:
    fps = 25.0
width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
if width <= 0 or height <= 0:
    print(json.dumps({{"ok": False, "error": "Invalid video size"}}))
    sys.exit(1)
device_value = r'{device}'.strip()
if device_value.lower() in ("", "auto", "cuda", "nv", "nvidia"):
    try:
        import torch
        device_value = "0" if torch.cuda.is_available() and torch.cuda.device_count() > 0 else "cpu"
    except Exception:
        device_value = "cpu"

def _rustlabel_predict(source):
    global device_value
    try:
        return model.predict(source, save=False, imgsz={imgsz},
            conf={conf}, iou={iou}, device=device_value, verbose=False, stream=False)
    except Exception as error:
        if str(device_value).lower() != "cpu":
            print(f"[rustlabel] CUDA predict failed, fallback to CPU: {{error}}", file=sys.stderr)
            device_value = "cpu"
            return model.predict(source, save=False, imgsz={imgsz},
                conf={conf}, iou={iou}, device=device_value, verbose=False, stream=False)
        raise

ffmpeg_cmd = [
    r'{ffmpeg_path}',
    "-y",
    "-loglevel", "error",
    "-f", "rawvideo",
    "-pix_fmt", "bgr24",
    "-s", f"{{width}}x{{height}}",
    "-r", str(fps),
    "-i", "pipe:0",
    "-an",
]

def _hidden_startupinfo():
    if os.name != "nt":
        return None, 0
    info = subprocess.STARTUPINFO()
    info.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    return info, 0x08000000

def _has_nvidia():
    try:
        startup, flags = _hidden_startupinfo()
        result = subprocess.run(
            ["nvidia-smi"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            startupinfo=startup,
            creationflags=flags,
        )
        return result.returncode == 0
    except Exception:
        return False

def _available_encoders():
    try:
        startup, flags = _hidden_startupinfo()
        result = subprocess.run(
            [r'{ffmpeg_path}', "-hide_banner", "-encoders"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            startupinfo=startup,
            creationflags=flags,
        )
        return result.stdout if result.returncode == 0 else ""
    except Exception:
        return ""

def _h264_codec_args():
    encoders = _available_encoders()
    if _has_nvidia() and "h264_nvenc" in encoders:
        return ["-c:v", "h264_nvenc", "-cq", "23"]
    if "h264_qsv" in encoders:
        return ["-c:v", "h264_qsv", "-global_quality", "23"]
    if "h264_amf" in encoders:
        return ["-c:v", "h264_amf", "-quality", "balanced"]
    return ["-c:v", "libx264", "-preset", "medium", "-crf", "23"]

ffmpeg_cmd += _h264_codec_args() + [
    "-pix_fmt", "yuv420p",
    "-movflags", "+faststart",
    r'{output_path}',
]
startupinfo = None
creationflags = 0
if os.name == "nt":
    startupinfo, creationflags = _hidden_startupinfo()
encoder = subprocess.Popen(
    ffmpeg_cmd,
    stdin=subprocess.PIPE,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
    startupinfo=startupinfo,
    creationflags=creationflags,
)
frame_idx = 0
label_count = 0
try:
    while True:
        ret, frame = cap.read()
        if not ret:
            break
        results = _rustlabel_predict(frame)
        annotated = frame
        for r in results:
            if r.boxes is not None:
                label_count = max(label_count, len(r.boxes))
            annotated = r.plot()
        if annotated.shape[1] != width or annotated.shape[0] != height:
            annotated = cv2.resize(annotated, (width, height), interpolation=cv2.INTER_LINEAR)
        encoder.stdin.write(np.ascontiguousarray(annotated).tobytes())
        frame_idx += 1
finally:
    cap.release()
    if encoder.stdin:
        encoder.stdin.close()
stderr = encoder.stderr.read().decode("utf-8", errors="replace") if encoder.stderr else ""
return_code = encoder.wait()
if return_code != 0:
    raise RuntimeError(f"FFmpeg H264 encode failed: {{stderr.strip()}}")
print(json.dumps({{"ok": True, "frame_count": frame_idx, "fps": fps,
    "width": width, "height": height, "label_count": label_count}}))
"##,
        model_path = req.model_path.replace('\\', "\\\\"),
        input_path = req.input_path.replace('\\', "\\\\"),
        output_path = output_path.to_string_lossy().replace('\\', "\\\\"),
        ffmpeg_path = req.ffmpeg_path.replace('\\', "\\\\"),
        imgsz = req.imgsz,
        conf = req.conf_threshold,
        iou = req.iou_threshold,
        device = req.device,
    );

    let stdout = match run_python_script(&python, &script, None) {
        Ok(s) => s,
        Err(e) => {
            return DetectResult {
                ok: false,
                output_path: String::new(),
                error: Some(e),
                label_count: 0,
            };
        }
    };

    let frame_count = parse_u32_field(&stdout, "frame_count").unwrap_or(0);
    let label_count = parse_u32_field(&stdout, "label_count").unwrap_or(0);

    if frame_count == 0 {
        return DetectResult {
            ok: false,
            output_path: String::new(),
            error: Some("No frames extracted".into()),
            label_count: 0,
        };
    }

    DetectResult {
        ok: true,
        output_path: output_path.to_string_lossy().into_owned(),
        error: None,
        label_count,
    }
}

fn verify_python(path: &str) -> Result<String, String> {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return Err("Python path not configured".into());
    }
    Ok(trimmed.to_string())
}

fn run_python_script(python: &str, script: &str, cwd: Option<&Path>) -> Result<String, String> {
    let tmp = std::env::temp_dir().join(format!("_yolo_detect_{}.py", std::process::id()));
    fs::write(&tmp, script).map_err(|e| format!("write script: {e}"))?;

    let mut cmd = Command::new(python);
    cmd.arg(&tmp);
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);

    let output = cmd.output().map_err(|e| format!("python start: {e}"))?;
    let _ = fs::remove_file(&tmp);

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("python error: {stderr}"));
    }
    Ok(stdout)
}

fn parse_label_count(stdout: &str) -> u32 {
    parse_json_u32(stdout, "label_count").unwrap_or(0)
}

fn model_task_to_folder(task: &str) -> String {
    match task.trim().to_ascii_lowercase().as_str() {
        "obb" => "obb".to_string(),
        "segment" | "seg" => "seg".to_string(),
        _ => "hbb".to_string(),
    }
}

fn parse_json_string(stdout: &str, key: &str) -> Option<String> {
    let needle = format!("\"{}\":", key);
    let start = stdout.find(&needle)? + needle.len();
    let rest = stdout[start..].trim_start();
    if !rest.starts_with('"') {
        return None;
    }
    let mut escaped = false;
    let mut value = String::new();
    for ch in rest[1..].chars() {
        if escaped {
            value.push(match ch {
                '"' => '"',
                '\\' => '\\',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                other => other,
            });
            escaped = false;
            continue;
        }
        match ch {
            '\\' => escaped = true,
            '"' => return Some(value),
            other => value.push(other),
        }
    }
    None
}

fn parse_u32_field(stdout: &str, key: &str) -> Option<u32> {
    parse_json_u32(stdout, key)
}

fn parse_json_u32(stdout: &str, key: &str) -> Option<u32> {
    let needle = format!("\"{}\":", key);
    let start = stdout.find(&needle)? + needle.len();
    let rest = &stdout[start..];
    let end = rest.find([',', '}']).unwrap_or(rest.len());
    rest[..end].trim().parse::<u32>().ok()
}
