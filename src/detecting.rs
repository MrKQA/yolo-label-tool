use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

use once_cell::sync::Lazy;

#[cfg(windows)]
use std::os::windows::process::CommandExt;

static DETECT_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));
static ACTIVE_PYTHON_CHILDREN: Lazy<Mutex<Vec<u32>>> = Lazy::new(|| Mutex::new(Vec::new()));
static PYTHON_SHUTDOWN_REQUESTED: AtomicBool = AtomicBool::new(false);

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

#[derive(Debug, Clone)]
pub struct AiAnnotateImageRequest {
    pub backend: String,
    pub python_path: String,
    pub model_path: String,
    pub input_path: String,
    pub class_ids_csv: String,
    pub conf_threshold: f64,
    pub iou_threshold: f64,
    pub imgsz: u32,
    pub device: String,
    pub sam_mode: String,
    pub sam_prompt_mode: String,
    pub prompts_text: String,
    pub sam_click_points_text: String,
    pub sam_precision: String,
    pub sam_encoder: String,
    pub sam_image_batch_size: u32,
    pub sam_video_batch_size: u32,
    pub sam_interactive_batch_size: u32,
    pub sam_max_image_width: u32,
    pub sam_max_image_height: u32,
    pub sam_resize_method: String,
}

#[derive(Debug, Clone)]
pub struct AiAnnotateBatchRequest {
    pub backend: String,
    pub python_path: String,
    pub model_path: String,
    pub input_paths_text: String,
    pub class_ids_csv: String,
    pub conf_threshold: f64,
    pub iou_threshold: f64,
    pub imgsz: u32,
    pub device: String,
    pub sam_mode: String,
    pub sam_prompt_mode: String,
    pub prompts_text: String,
    pub sam_click_points_text: String,
    pub sam_precision: String,
    pub sam_encoder: String,
    pub sam_image_batch_size: u32,
    pub sam_video_batch_size: u32,
    pub sam_interactive_batch_size: u32,
    pub sam_max_image_width: u32,
    pub sam_max_image_height: u32,
    pub sam_resize_method: String,
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
model = YOLO({model_path})
task = str(getattr(model, "task", "") or "detect")
print(json.dumps({{"ok": True, "task": task}}))
"##,
        model_path = python_string_literal(model_path),
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

pub fn ai_model_classes_json(python_path: &str, model_path: &str) -> Result<String, String> {
    let python = verify_python(python_path)?;
    let script = format!(
        r##"import json, os
os.environ["ULTRALYTICS_TQDM"] = "false"
os.environ["YOLO_VERBOSE"] = "false"
from ultralytics import YOLO
model = YOLO({model_path})
names = getattr(model, "names", {{}}) or {{}}
items = []
if isinstance(names, dict):
    for key, value in names.items():
        try:
            items.append({{"id": int(key), "name": str(value)}})
        except Exception:
            pass
else:
    for index, value in enumerate(names):
        items.append({{"id": int(index), "name": str(value)}})
items.sort(key=lambda item: item["id"])
task = str(getattr(model, "task", "") or "detect")
print(json.dumps({{"ok": True, "task": task, "classes": items}}, ensure_ascii=False))
"##,
        model_path = python_string_literal(model_path),
    );
    run_python_script(&python, &script, None)
}

pub fn ai_annotate_image_json(req: &AiAnnotateImageRequest) -> Result<String, String> {
    if req.backend.trim().eq_ignore_ascii_case("sam3") {
        return ai_annotate_sam3_image_json(req);
    }
    let python = verify_python(&req.python_path)?;
    let script = format!(
        r##"import sys, json, os
os.environ["ULTRALYTICS_TQDM"] = "false"
os.environ["YOLO_VERBOSE"] = "false"
from ultralytics import YOLO
model = YOLO({model_path})
device_value = {device}.strip()
if device_value.lower() in ("", "auto", "cuda", "nv", "nvidia"):
    try:
        import torch
        device_value = "0" if torch.cuda.is_available() and torch.cuda.device_count() > 0 else "cpu"
    except Exception:
        device_value = "cpu"
classes_raw = {class_ids_csv}.strip()
class_filter = None
if classes_raw:
    class_filter = [int(item) for item in classes_raw.split(",") if item.strip()]

def _rustlabel_predict():
    global device_value
    kwargs = dict(source={input_path}, save=False, imgsz={imgsz},
        conf={conf}, iou={iou}, device=device_value, verbose=False, stream=False)
    if class_filter is not None:
        kwargs["classes"] = class_filter
    try:
        return model.predict(**kwargs)
    except Exception as error:
        if str(device_value).lower() != "cpu":
            print(f"[rustlabel] CUDA predict failed, fallback to CPU: {{error}}", file=sys.stderr)
            device_value = "cpu"
            kwargs["device"] = "cpu"
            return model.predict(**kwargs)
        raise

results = _rustlabel_predict()
names = getattr(model, "names", {{}}) or {{}}
boxes = []
width = 0
height = 0
for r in results:
    shape = getattr(r, "orig_shape", None)
    if shape and len(shape) >= 2:
        height = int(shape[0])
        width = int(shape[1])
    if getattr(r, "boxes", None) is None:
        continue
    for box in r.boxes:
        cls_id = int(box.cls[0].item()) if getattr(box, "cls", None) is not None else 0
        conf_value = float(box.conf[0].item()) if getattr(box, "conf", None) is not None else 0.0
        xyxy = box.xyxy[0].tolist()
        name = names.get(cls_id, f"class_{{cls_id}}") if isinstance(names, dict) else (
            names[cls_id] if cls_id < len(names) else f"class_{{cls_id}}"
        )
        boxes.append({{
            "classId": cls_id,
            "className": str(name),
            "confidence": conf_value,
            "left": float(xyxy[0]),
            "top": float(xyxy[1]),
            "right": float(xyxy[2]),
            "bottom": float(xyxy[3]),
        }})
print(json.dumps({{"ok": True, "width": width, "height": height, "boxes": boxes}}, ensure_ascii=False))
"##,
        model_path = python_string_literal(&req.model_path),
        input_path = python_string_literal(&req.input_path),
        class_ids_csv = python_string_literal(&req.class_ids_csv),
        imgsz = req.imgsz,
        conf = req.conf_threshold,
        iou = req.iou_threshold,
        device = req.device,
    );
    run_python_script(&python, &script, None)
}

pub fn ai_annotate_images_json(req: &AiAnnotateBatchRequest) -> Result<String, String> {
    ai_annotate_images_json_with_sam_prompt_frame(req, 0)
}

pub fn ai_annotate_images_json_with_sam_prompt_frame(
    req: &AiAnnotateBatchRequest,
    sam_prompt_frame_index: u32,
) -> Result<String, String> {
    if req.backend.trim().eq_ignore_ascii_case("sam3") {
        return ai_annotate_sam3_images_json(req, sam_prompt_frame_index);
    }
    let python = verify_python(&req.python_path)?;
    let script = format!(
        r##"import sys, json, os
os.environ["ULTRALYTICS_TQDM"] = "false"
os.environ["YOLO_VERBOSE"] = "false"
from ultralytics import YOLO
model = YOLO({model_path})
source_paths = {input_paths}
device_value = {device}.strip()
if device_value.lower() in ("", "auto", "cuda", "nv", "nvidia"):
    try:
        import torch
        device_value = "0" if torch.cuda.is_available() and torch.cuda.device_count() > 0 else "cpu"
    except Exception:
        device_value = "cpu"
classes_raw = {class_ids_csv}.strip()
class_filter = None
if classes_raw:
    class_filter = [int(item) for item in classes_raw.split(",") if item.strip()]

def _rustlabel_predict():
    global device_value
    kwargs = dict(source=source_paths, save=False, imgsz={imgsz},
        conf={conf}, iou={iou}, device=device_value, verbose=False, stream=True)
    if class_filter is not None:
        kwargs["classes"] = class_filter
    try:
        return model.predict(**kwargs)
    except Exception as error:
        if str(device_value).lower() != "cpu":
            print(f"[rustlabel] CUDA batch predict failed, fallback to CPU: {{error}}", file=sys.stderr)
            device_value = "cpu"
            kwargs["device"] = "cpu"
            return model.predict(**kwargs)
        raise

names = getattr(model, "names", {{}}) or {{}}
images = []
for index, r in enumerate(_rustlabel_predict()):
    shape = getattr(r, "orig_shape", None)
    height = int(shape[0]) if shape and len(shape) >= 2 else 0
    width = int(shape[1]) if shape and len(shape) >= 2 else 0
    input_path = str(getattr(r, "path", "") or (source_paths[index] if index < len(source_paths) else ""))
    boxes = []
    if getattr(r, "boxes", None) is not None:
        for box in r.boxes:
            cls_id = int(box.cls[0].item()) if getattr(box, "cls", None) is not None else 0
            conf_value = float(box.conf[0].item()) if getattr(box, "conf", None) is not None else 0.0
            xyxy = box.xyxy[0].tolist()
            name = names.get(cls_id, f"class_{{cls_id}}") if isinstance(names, dict) else (
                names[cls_id] if cls_id < len(names) else f"class_{{cls_id}}"
            )
            boxes.append({{
                "classId": cls_id,
                "className": str(name),
                "confidence": conf_value,
                "left": float(xyxy[0]),
                "top": float(xyxy[1]),
                "right": float(xyxy[2]),
                "bottom": float(xyxy[3]),
            }})
    images.append({{
        "inputPath": input_path,
        "width": width,
        "height": height,
        "boxes": boxes,
    }})
print(json.dumps({{"ok": True, "images": images}}, ensure_ascii=False))
"##,
        model_path = python_string_literal(&req.model_path),
        input_paths = python_string_list_literal(&req.input_paths_text),
        class_ids_csv = python_string_literal(&req.class_ids_csv),
        imgsz = req.imgsz,
        conf = req.conf_threshold,
        iou = req.iou_threshold,
        device = req.device,
    );
    run_python_script(&python, &script, None)
}

fn ai_annotate_sam3_image_json(req: &AiAnnotateImageRequest) -> Result<String, String> {
    let python = verify_python(&req.python_path)?;
    let script = sam3_script(
        &req.model_path,
        &format!("[{}]", python_string_literal(&req.input_path)),
        &req.sam_prompt_mode,
        &req.prompts_text,
        &req.sam_click_points_text,
        req.conf_threshold,
        &req.device,
        &req.sam_precision,
        &req.sam_encoder,
        req.sam_image_batch_size,
        req.sam_video_batch_size,
        req.sam_interactive_batch_size,
        req.sam_max_image_width,
        req.sam_max_image_height,
        &req.sam_resize_method,
        0,
    );
    run_python_json_script(&python, &script, None).map_err(classify_python_error)
}

fn ai_annotate_sam3_images_json(
    req: &AiAnnotateBatchRequest,
    sam_prompt_frame_index: u32,
) -> Result<String, String> {
    let python = verify_python(&req.python_path)?;
    let script = sam3_script(
        &req.model_path,
        &python_string_list_literal(&req.input_paths_text),
        &req.sam_prompt_mode,
        &req.prompts_text,
        &req.sam_click_points_text,
        req.conf_threshold,
        &req.device,
        &req.sam_precision,
        &req.sam_encoder,
        req.sam_image_batch_size,
        req.sam_video_batch_size,
        req.sam_interactive_batch_size,
        req.sam_max_image_width,
        req.sam_max_image_height,
        &req.sam_resize_method,
        sam_prompt_frame_index,
    );
    run_python_json_script(&python, &script, None).map_err(classify_python_error)
}

fn sam3_script(
    model_path: &str,
    input_paths_literal: &str,
    prompt_mode: &str,
    prompts_text: &str,
    click_points_text: &str,
    conf_threshold: f64,
    device: &str,
    precision: &str,
    encoder: &str,
    image_batch_size: u32,
    video_batch_size: u32,
    interactive_batch_size: u32,
    max_image_width: u32,
    max_image_height: u32,
    resize_method: &str,
    prompt_frame_index: u32,
) -> String {
    format!(
        r##"import json, os, sys, traceback
os.environ["PYTORCH_CUDA_ALLOC_CONF"] = os.environ.get("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
model_path = {model_path}
source_paths = {input_paths}
prompt_mode = {prompt_mode}.strip().lower() or "text"
prompts = {prompts}
click_points_raw = {click_points}
conf_threshold = float({conf})
device_value = {device}.strip().lower()
precision = {precision}.strip().lower()
encoder = {encoder}.strip().lower()
image_batch_size = int({image_batch_size})
video_batch_size = int({video_batch_size})
interactive_batch_size = int({interactive_batch_size})
max_image_width = max(64, int({max_image_width}))
max_image_height = max(64, int({max_image_height}))
resize_method = {resize_method}.strip().lower() or "shorter_side"
prompt_frame_index = int({prompt_frame_index})
processor_resolution = 1008

def _parse_click_points(raw):
    items = []
    for line in str(raw or "").replace("\r", "\n").split("\n"):
        line = line.strip()
        if not line:
            continue
        parts = [part.strip() for part in line.split(",")]
        if len(parts) < 3:
            continue
        try:
            x = max(0.0, min(1.0, float(parts[0])))
            y = max(0.0, min(1.0, float(parts[1])))
        except Exception:
            continue
        label_text = parts[2].lower()
        positive = label_text in ("1", "true", "yes", "positive", "pos", "fg", "foreground")
        items.append((x, y, positive))
    return items

click_points = _parse_click_points(click_points_raw)
print(
    f"[rustlabel][sam3] start images={{len(source_paths)}} prompts={{len(prompts)}} "
    f"prompt_mode={{prompt_mode}} click_points={{len(click_points)}} precision={{precision}} encoder={{encoder}} "
    f"batch=image:{{image_batch_size}}/video:{{video_batch_size}}/interactive:{{interactive_batch_size}} "
    f"pre_resize={{max_image_width}}x{{max_image_height}} resize_method={{resize_method}} "
    f"prompt_frame={{prompt_frame_index}} processor_resolution={{processor_resolution}}",
    file=sys.stderr,
)
if prompt_mode not in ("text", "click"):
    raise RuntimeError(f"SAM3 prompt mode must be text or click, got {{prompt_mode}}")
if prompt_mode == "text" and not prompts:
    raise RuntimeError("SAM3 text prompt is empty")
if prompt_mode == "click" and not click_points:
    raise RuntimeError("SAM3 click prompt needs at least one point")
if prompt_mode == "click" and not any(item[2] for item in click_points):
    raise RuntimeError("SAM3 click prompt needs at least one positive point")
if encoder and encoder != "vit_b":
    raise RuntimeError(f"SAM3 low-memory preset only allows encoder=vit_b, got {{encoder}}")

try:
    import importlib.util
    import platform
    is_windows = platform.system().lower() == "windows"
    triton_package = "triton-windows" if is_windows else "triton"
    required_modules = [
        ("numpy", "numpy"),
        ("torch", "torch"),
        ("PIL", "pillow"),
        ("sam3", "sam3"),
        ("einops", "einops"),
        ("triton", triton_package),
    ]
    missing = [pkg for module, pkg in required_modules if importlib.util.find_spec(module) is None]
    if missing:
        hint = ""
        if "triton-windows" in missing:
            hint = " On native Windows, install Triton with: python -m pip install triton-windows."
        raise RuntimeError(
            f"SAM3 dependency import failed: missing packages: {{', '.join(missing)}}. "
            f"Install the SAM3 repository requirements into this Python environment.{{hint}}"
        )
except RuntimeError:
    raise
except Exception as error:
    raise RuntimeError(f"SAM3 dependency precheck failed: {{type(error).__name__}}: {{error}}")

try:
    import numpy as np
    import torch
    from PIL import Image
    from sam3.model_builder import build_sam3_image_model, build_sam3_video_model
    from sam3.model.sam3_image_processor import Sam3Processor
except Exception as error:
    windows_hint = ""
    try:
        import platform as _rustlabel_platform
        if "triton" in str(error).lower() and _rustlabel_platform.system().lower() == "windows":
            windows_hint = " On native Windows, install Triton with: python -m pip install triton-windows."
    except Exception:
        pass
    raise RuntimeError(
        f"SAM3 dependency import failed. Install the SAM3 repository requirements into this Python environment. "
        f"Original error: {{type(error).__name__}}: {{error}}{{windows_hint}}"
    )

try:
    import cv2
except Exception:
    cv2 = None
    print("[rustlabel][sam3] cv2 is unavailable; using numpy boundary polygon fallback", file=sys.stderr)

if device_value in ("", "auto", "cuda", "nv", "nvidia"):
    device_value = "cuda" if torch.cuda.is_available() else "cpu"
if device_value.startswith("cuda") and not torch.cuda.is_available():
    print("[rustlabel][sam3] CUDA requested but unavailable, fallback to CPU", file=sys.stderr)
    device_value = "cpu"
torch_device = torch.device(device_value)
device_name = "cuda" if torch_device.type == "cuda" else "cpu"
interactive_enabled = prompt_mode == "click"
video_click_enabled = interactive_enabled and len(source_paths) > 1

def _build_image_model():
    attempts = []
    def with_model_options(kwargs):
        kwargs = dict(kwargs)
        kwargs["enable_inst_interactivity"] = interactive_enabled
        return kwargs
    if model_path:
        attempts.extend([
            with_model_options(dict(checkpoint_path=model_path, device=device_name)),
            with_model_options(dict(ckpt_path=model_path, device=device_name)),
            with_model_options(dict(checkpoint=model_path, device=device_name)),
            with_model_options(dict(device=device_name)),
        ])
    else:
        attempts.append(with_model_options(dict(device=device_name)))
    last_error = None
    for kwargs in attempts:
        try:
            return build_sam3_image_model(**kwargs)
        except TypeError as error:
            last_error = error
            continue
    try:
        model = build_sam3_image_model(enable_inst_interactivity=interactive_enabled)
        if hasattr(model, "to"):
            model = model.to(torch_device)
        return model
    except Exception as error:
        last_error = error
    raise RuntimeError(f"SAM3 model load failed: {{last_error}}")

def _build_video_model():
    attempts = []
    if model_path:
        attempts.extend([
            dict(checkpoint_path=model_path, device=device_name, compile=False),
            dict(checkpoint_path=model_path, device=device_name),
        ])
    else:
        attempts.append(dict(device=device_name, compile=False))
    last_error = None
    for kwargs in attempts:
        try:
            return build_sam3_video_model(**kwargs)
        except TypeError as error:
            last_error = error
            continue
    try:
        return build_sam3_video_model()
    except Exception as error:
        last_error = error
    raise RuntimeError(f"SAM3-Video model load failed: {{last_error}}")

def _disable_windows_cc_cleanup(loaded_model):
    try:
        # Disable interactive mask cleanup that triggers connected-components
        # Triton/CUDA JIT on Windows. It only fills tiny holes/sprinkles, while
        # failed JIT can print non-JSON compiler logs to stdout or abort preview.
        predictor = getattr(loaded_model, "inst_interactive_predictor", None)
        if predictor is not None and getattr(predictor, "_transforms", None) is not None:
            predictor._transforms.max_hole_area = 0.0
            predictor._transforms.max_sprinkle_area = 0.0
        if hasattr(loaded_model, "fill_hole_area"):
            loaded_model.fill_hole_area = 0
        print("[rustlabel][sam3] disabled interactive mask postprocess connected-components", file=sys.stderr)
    except Exception as error:
        print(f"[rustlabel][sam3] failed to disable interactive postprocess: {{error}}", file=sys.stderr)

model = None
processor = None
if not video_click_enabled:
    model = _build_image_model()
    if hasattr(model, "eval"):
        model.eval()
    if interactive_enabled and getattr(model, "inst_interactive_predictor", None) is None:
        raise RuntimeError("SAM3 click mode requires enable_inst_interactivity=True, but the model has no interactive predictor")
    if interactive_enabled:
        _disable_windows_cc_cleanup(model)
    processor = Sam3Processor(model, confidence_threshold=conf_threshold, resolution=processor_resolution, device=device_name)

def _autocast():
    if torch_device.type != "cuda":
        return torch.autocast(device_type="cpu", enabled=False)
    if precision == "fp16":
        return torch.autocast(device_type="cuda", dtype=torch.float16)
    if precision == "bf16":
        return torch.autocast(device_type="cuda", dtype=torch.bfloat16)
    return torch.autocast(device_type="cuda", enabled=False)

def _to_numpy(value):
    if value is None:
        return None
    if hasattr(value, "detach"):
        return value.detach().float().cpu().numpy()
    return np.asarray(value)

def _mask_to_polygon(mask):
    arr = np.asarray(mask)
    while arr.ndim > 2:
        arr = arr[0]
    arr = arr > 0.5
    h, w = arr.shape[:2]
    if h <= 0 or w <= 0 or not arr.any():
        return []
    if cv2 is not None:
        contours, _ = cv2.findContours(arr.astype("uint8"), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if contours:
            contour = max(contours, key=cv2.contourArea)
            epsilon = max(1.5, 0.0025 * cv2.arcLength(contour, True))
            approx = cv2.approxPolyDP(contour, epsilon, True)
            return [[float(p[0][0]), float(p[0][1])] for p in approx]
    padded = np.pad(arr, 1, constant_values=False)
    interior = (
        padded[1:-1, 1:-1]
        & padded[:-2, 1:-1]
        & padded[2:, 1:-1]
        & padded[1:-1, :-2]
        & padded[1:-1, 2:]
    )
    boundary = arr & ~interior
    ys, xs = np.where(boundary)
    if xs.size >= 3:
        unique_xs = np.unique(xs)
        max_columns = 256
        if unique_xs.size > max_columns:
            step = int(np.ceil(unique_xs.size / max_columns))
            unique_xs = unique_xs[::step]
        top = []
        bottom = []
        for x in unique_xs:
            column_ys = ys[xs == x]
            if column_ys.size == 0:
                continue
            top.append([float(x), float(column_ys.min())])
            bottom.append([float(x), float(column_ys.max())])
        points = top + list(reversed(bottom))
        compact = []
        for point in points:
            if not compact or compact[-1] != point:
                compact.append(point)
        if len(compact) >= 3:
            return compact
    ys, xs = np.where(arr)
    left, right = float(xs.min()), float(xs.max())
    top, bottom = float(ys.min()), float(ys.max())
    return [[left, top], [right, top], [right, bottom], [left, bottom]]

def _extract_masks_for_size(output, prompt_index, prompt, output_width, output_height):
    masks = _to_numpy(output.get("masks") if isinstance(output, dict) else None)
    scores = _to_numpy(output.get("scores") if isinstance(output, dict) else None)
    if masks is None:
        return []
    if masks.ndim == 2:
        masks = masks[None, :, :]
    items = []
    for idx, mask in enumerate(masks):
        points = _mask_to_polygon(mask)
        if len(points) < 3:
            continue
        mh, mw = np.asarray(mask).squeeze().shape[-2:]
        if mw > 0 and mh > 0:
            points = [[x / mw * output_width, y / mh * output_height] for x, y in points]
        score = 0.0
        if scores is not None and scores.size > idx:
            score = float(scores.reshape(-1)[idx])
        items.append({{
            "classId": int(prompt_index),
            "className": str(prompt),
            "confidence": score,
            "points": points,
        }})
    return items

def _extract_masks(output, prompt_index, prompt):
    return _extract_masks_for_size(output, prompt_index, prompt, current_width, current_height)

def _extract_video_masks(output, prompt, output_width, output_height):
    if not isinstance(output, dict):
        return []
    masks = output.get("out_binary_masks")
    scores = output.get("out_probs")
    return _extract_masks_for_size({{"masks": masks, "scores": scores}}, 0, prompt, output_width, output_height)

def _preprocess_image(image):
    original_width, original_height = image.size
    if original_width <= 0 or original_height <= 0:
        return image
    if original_width <= max_image_width and original_height <= max_image_height:
        return image
    # Keep aspect ratio. "shorter_side" is currently constrained by max_image_size
    # so the result never exceeds either width or height limits.
    scale = min(max_image_width / original_width, max_image_height / original_height)
    scale = min(1.0, max(scale, 1e-6))
    next_size = (
        max(1, int(round(original_width * scale))),
        max(1, int(round(original_height * scale))),
    )
    if next_size == image.size:
        return image
    return image.resize(next_size, Image.Resampling.LANCZOS)

def _run_video_click_annotation():
    prompt_name = prompts[0] if prompts else "sam3_click"
    safe_prompt_frame_index = max(0, min(int(prompt_frame_index), len(source_paths) - 1))
    if safe_prompt_frame_index != prompt_frame_index:
        print(
            f"[rustlabel][sam3-video] prompt frame {{prompt_frame_index}} is out of range; using {{safe_prompt_frame_index}}",
            file=sys.stderr,
        )
    video_frames = []
    frame_sizes = []
    sequence_size = None
    for path in source_paths:
        image = Image.open(path).convert("RGB")
        original_width, original_height = image.size
        image = _preprocess_image(image)
        current_width, current_height = image.size
        if (current_width, current_height) != (original_width, original_height):
            print(
                f"[rustlabel][sam3-video] preprocess frame={{path}} {{original_width}}x{{original_height}} -> {{current_width}}x{{current_height}} method={{resize_method}}",
                file=sys.stderr,
            )
        if sequence_size is None:
            sequence_size = (current_width, current_height)
        elif (current_width, current_height) != sequence_size:
            print(
                f"[rustlabel][sam3-video] frame={{path}} size={{current_width}}x{{current_height}} differs from sequence {{sequence_size[0]}}x{{sequence_size[1]}}; resizing for video propagation",
                file=sys.stderr,
            )
            image = image.resize(sequence_size, Image.Resampling.LANCZOS)
            current_width, current_height = sequence_size
        video_frames.append(image)
        frame_sizes.append((current_width, current_height))
    if not video_frames:
        return []
    print(
        f"[rustlabel][sam3-video] init frames={{len(video_frames)}} prompt_frame={{safe_prompt_frame_index}} size={{frame_sizes[0][0]}}x{{frame_sizes[0][1]}}",
        file=sys.stderr,
    )
    video_model = _build_video_model()
    if hasattr(video_model, "eval"):
        video_model.eval()
    _disable_windows_cc_cleanup(video_model)
    point_coords = torch.as_tensor(
        [[x, y] for x, y, _ in click_points],
        dtype=torch.float32,
    )
    point_labels = torch.as_tensor(
        [1 if positive else 0 for _, _, positive in click_points],
        dtype=torch.int32,
    )
    results_by_frame = {{}}
    with torch.inference_mode():
        with _autocast():
            inference_state = video_model.init_state(
                resource_path=video_frames,
                offload_video_to_cpu=torch_device.type != "cuda",
            )
            frame_idx, output = video_model.add_prompt(
                inference_state,
                frame_idx=safe_prompt_frame_index,
                points=point_coords,
                point_labels=point_labels,
                obj_id=10000,
                rel_coordinates=True,
            )
            if output is not None:
                results_by_frame[int(frame_idx)] = output
            max_forward = len(video_frames) - safe_prompt_frame_index
            for frame_idx, output in video_model.propagate_in_video(
                inference_state,
                start_frame_idx=safe_prompt_frame_index,
                max_frame_num_to_track=max_forward,
                reverse=False,
            ):
                if output is not None:
                    results_by_frame[int(frame_idx)] = output
            if safe_prompt_frame_index > 0:
                max_backward = safe_prompt_frame_index + 1
                for frame_idx, output in video_model.propagate_in_video(
                    inference_state,
                    start_frame_idx=safe_prompt_frame_index,
                    max_frame_num_to_track=max_backward,
                    reverse=True,
                ):
                    if output is not None:
                        results_by_frame[int(frame_idx)] = output
    annotated_images = []
    for index, path in enumerate(source_paths):
        current_width, current_height = frame_sizes[index]
        masks = _extract_video_masks(
            results_by_frame.get(index),
            prompt_name,
            current_width,
            current_height,
        )
        annotated_images.append({{
            "inputPath": str(path),
            "width": int(current_width),
            "height": int(current_height),
            "boxes": [],
            "masks": masks,
        }})
        print(
            f"[rustlabel][sam3-video] frame={{index}} image={{path}} masks={{len(masks)}}",
            file=sys.stderr,
        )
    return annotated_images

if video_click_enabled:
    images = _run_video_click_annotation()
    print(json.dumps({{"ok": True, "images": images}}, ensure_ascii=False))
    sys.exit(0)

images = []
for path in source_paths:
    try:
        image = Image.open(path).convert("RGB")
        original_width, original_height = image.size
        image = _preprocess_image(image)
        current_width, current_height = image.size
        if (current_width, current_height) != (original_width, original_height):
            print(
                f"[rustlabel][sam3] preprocess image={{path}} {{original_width}}x{{original_height}} -> {{current_width}}x{{current_height}} method={{resize_method}}",
                file=sys.stderr,
            )
        masks = []
        with torch.inference_mode():
            with _autocast():
                state = processor.set_image(image)
                if prompt_mode == "click":
                    prompt_name = prompts[0] if prompts else "sam3_click"
                    point_coords = np.asarray(
                        [[x * current_width, y * current_height] for x, y, _ in click_points],
                        dtype=np.float32,
                    )
                    point_labels = np.asarray(
                        [1 if positive else 0 for _, _, positive in click_points],
                        dtype=np.int32,
                    )
                    predicted_masks, predicted_scores, _ = model.predict_inst(
                        state,
                        point_coords=point_coords,
                        point_labels=point_labels,
                        multimask_output=len(click_points) == 1,
                        return_logits=False,
                        normalize_coords=True,
                    )
                    predicted_masks = np.asarray(predicted_masks)
                    predicted_scores = np.asarray(predicted_scores).reshape(-1)
                    if predicted_masks.ndim == 2:
                        predicted_masks = predicted_masks[None, :, :]
                    if predicted_masks.ndim >= 3 and predicted_masks.shape[0] > 1:
                        best_idx = 0
                        if predicted_scores.size > 0:
                            best_idx = int(np.argmax(predicted_scores[: predicted_masks.shape[0]]))
                        predicted_masks = predicted_masks[best_idx : best_idx + 1]
                        if predicted_scores.size > 0:
                            predicted_scores = predicted_scores[best_idx : best_idx + 1]
                    masks.extend(_extract_masks({{"masks": predicted_masks, "scores": predicted_scores}}, 0, prompt_name))
                else:
                    for prompt_index, prompt in enumerate(prompts):
                        output = processor.set_text_prompt(state=state, prompt=prompt)
                        masks.extend(_extract_masks(output, prompt_index, prompt))
        images.append({{
            "inputPath": str(path),
            "width": int(current_width),
            "height": int(current_height),
            "boxes": [],
            "masks": masks,
        }})
        print(f"[rustlabel][sam3] image={{path}} masks={{len(masks)}}", file=sys.stderr)
    except RuntimeError as error:
        message = str(error)
        if "out of memory" in message.lower():
            raise RuntimeError(f"SAM3 OOM while processing {{path}}: {{message}}")
        raise

if len(images) == 1:
    item = images[0]
    print(json.dumps({{"ok": True, "width": item["width"], "height": item["height"], "boxes": [], "masks": item["masks"]}}, ensure_ascii=False))
else:
    print(json.dumps({{"ok": True, "images": images}}, ensure_ascii=False))
"##,
        model_path = python_string_literal(model_path),
        input_paths = input_paths_literal,
        prompt_mode = python_string_literal(prompt_mode),
        prompts = python_string_list_literal(prompts_text),
        click_points = python_string_literal(click_points_text),
        conf = conf_threshold,
        device = python_string_literal(device),
        precision = python_string_literal(precision),
        encoder = python_string_literal(encoder),
        resize_method = python_string_literal(resize_method),
        image_batch_size = image_batch_size.max(1),
        video_batch_size = video_batch_size.max(1),
        interactive_batch_size = interactive_batch_size.max(1),
        max_image_width = max_image_width.max(64),
        max_image_height = max_image_height.max(64),
        prompt_frame_index = prompt_frame_index,
    )
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

fn python_string_literal(value: &str) -> String {
    let mut result = String::from("'");
    for ch in value.chars() {
        match ch {
            '\\' => result.push_str("\\\\"),
            '\'' => result.push_str("\\'"),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            _ => result.push(ch),
        }
    }
    result.push('\'');
    result
}

fn python_string_list_literal(lines: &str) -> String {
    let values = lines
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(python_string_literal)
        .collect::<Vec<_>>()
        .join(", ");
    format!("[{values}]")
}

fn run_python_script(python: &str, script: &str, cwd: Option<&Path>) -> Result<String, String> {
    if PYTHON_SHUTDOWN_REQUESTED.load(Ordering::SeqCst) {
        return Err("Python backend is shutting down".to_string());
    }
    let tmp = std::env::temp_dir().join(format!(
        "_yolo_detect_{}_{}.py",
        std::process::id(),
        unix_millis_now()
    ));
    fs::write(&tmp, script).map_err(|e| format!("write script: {e}"))?;

    let mut cmd = Command::new(python);
    cmd.arg(&tmp);
    if let Some(dir) = cwd {
        cmd.current_dir(dir);
    }
    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());

    let child = cmd.spawn().map_err(|e| format!("python start: {e}"))?;
    let child_id = child.id();
    register_python_child(child_id);
    let output = child.wait_with_output();
    unregister_python_child(child_id);
    let _ = fs::remove_file(&tmp);
    let output = output.map_err(|e| format!("python wait: {e}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        let mut message = format!("python error: exit status {}", output.status);
        let stderr = stderr.trim();
        if !stderr.is_empty() {
            message.push_str("\nstderr:\n");
            message.push_str(stderr);
        }
        let stdout = stdout.trim();
        if !stdout.is_empty() {
            message.push_str("\nstdout:\n");
            message.push_str(stdout);
        }
        return Err(message);
    }
    Ok(stdout)
}

fn run_python_json_script(
    python: &str,
    script: &str,
    cwd: Option<&Path>,
) -> Result<String, String> {
    let stdout = run_python_script(python, script, cwd)?;
    extract_json_from_python_stdout(&stdout)
}

fn extract_json_from_python_stdout(stdout: &str) -> Result<String, String> {
    let trimmed = stdout.trim();
    if trimmed.starts_with('{') && trimmed.ends_with('}') {
        return Ok(trimmed.to_string());
    }
    for line in stdout.lines().rev() {
        let candidate = line.trim();
        if candidate.starts_with('{') && candidate.ends_with('}') {
            return Ok(candidate.to_string());
        }
    }
    let preview = trimmed.chars().take(12_000).collect::<String>();
    if preview.is_empty() {
        Err("python finished without JSON response".to_string())
    } else {
        Err(format!(
            "python finished without JSON response\nstdout:\n{}",
            preview
        ))
    }
}

fn classify_python_error(error: String) -> String {
    let lower = error.to_lowercase();
    let kind = if lower.contains("out of memory")
        || lower.contains("cuda oom")
        || lower.contains("cublas_status_alloc_failed")
        || lower.contains("memoryerror")
    {
        "oom"
    } else if lower.contains("no module named")
        || lower.contains("modulenotfounderror")
        || lower.contains("dependency import failed")
        || lower.contains("failed to compile")
        || lower.contains("cc_cmd")
        || lower.contains("triton")
    {
        "dependency"
    } else if lower.contains("sam3") {
        "sam3"
    } else {
        "runtime"
    };
    format!("{kind}: {error}")
}

pub fn shutdown_python_children() -> usize {
    PYTHON_SHUTDOWN_REQUESTED.store(true, Ordering::SeqCst);
    let children = {
        let mut active = ACTIVE_PYTHON_CHILDREN.lock().unwrap();
        let children = active.clone();
        active.clear();
        children
    };
    for child_id in &children {
        terminate_process_tree(*child_id);
    }
    children.len()
}

fn register_python_child(child_id: u32) {
    ACTIVE_PYTHON_CHILDREN.lock().unwrap().push(child_id);
}

fn unregister_python_child(child_id: u32) {
    let mut active = ACTIVE_PYTHON_CHILDREN.lock().unwrap();
    active.retain(|id| *id != child_id);
}

fn terminate_process_tree(process_id: u32) {
    #[cfg(windows)]
    {
        let mut command = Command::new("taskkill");
        command.args(["/PID", &process_id.to_string(), "/T", "/F"]);
        command.stdout(Stdio::null()).stderr(Stdio::null());
        command.creation_flags(CREATE_NO_WINDOW);
        let _ = command.status();
    }
    #[cfg(not(windows))]
    {
        let _ = Command::new("kill")
            .args(["-TERM", &process_id.to_string()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

fn unix_millis_now() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or(0)
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
