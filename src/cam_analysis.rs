use once_cell::sync::Lazy;
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

use super::detecting_mod;
use super::ini_python;

static CAM_ANALYSIS_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

#[derive(Debug, Clone)]
pub struct CamAnalysisRequest {
    pub python_path: String,
    pub model_path: String,
    pub input_path: String,
    pub output_dir: String,
    pub conf_threshold: f64,
    pub iou_threshold: f64,
    pub imgsz: u32,
    pub device: String,
    pub mode: String,
    pub smoothing: String,
    pub target_layer_index: i32,
    pub target_class_id: i32,
}

pub fn analyze_cam(req: &CamAnalysisRequest) -> Result<String, String> {
    let _guard = CAM_ANALYSIS_LOCK
        .lock()
        .map_err(|_| "CAM analysis lock is poisoned".to_string())?;
    let python = ini_python::verify_python_path(&req.python_path)?;
    let model_path = PathBuf::from(req.model_path.trim());
    if !model_path.is_file() {
        return Err(format!(
            "CAM model does not exist: {}",
            model_path.display()
        ));
    }
    if !model_path
        .extension()
        .and_then(|value| value.to_str())
        .is_some_and(|value| value.eq_ignore_ascii_case("pt"))
    {
        return Err("CAM analysis currently supports PyTorch .pt models only".to_string());
    }
    let input_path = PathBuf::from(req.input_path.trim());
    if !input_path.is_file() {
        return Err(format!(
            "CAM input image does not exist: {}",
            input_path.display()
        ));
    }
    let output_dir = PathBuf::from(req.output_dir.trim());
    fs::create_dir_all(&output_dir)
        .map_err(|error| format!("Failed to create CAM output directory: {error}"))?;

    let script = format!(
        r###"import gc
import json
import math
import os
import sys
import time

os.environ["ULTRALYTICS_TQDM"] = "false"
os.environ["YOLO_VERBOSE"] = "false"

try:
    import cv2
    import numpy as np
    import torch
    import torch.nn as nn
    import ultralytics
    from ultralytics import YOLO
except Exception as error:
    raise RuntimeError(
        "CAM dependency import failed. Install ultralytics, torch, opencv-python and numpy. "
        f"Original error: {{type(error).__name__}}: {{error}}"
    ) from error

try:
    from pytorch_grad_cam import EigenCAM, GradCAM, GradCAMPlusPlus, ScoreCAM, XGradCAM
except Exception as error:
    raise RuntimeError(
        "CAM dependency import failed. Install it with: pip install grad-cam. "
        f"Original error: {{type(error).__name__}}: {{error}}"
    ) from error

model_path = {model_path}
input_path = {input_path}
output_dir = {output_dir}
requested_device = {device}.strip()
analysis_mode = {mode}.strip().lower()
smoothing_mode = {smoothing}.strip().lower()
target_layer_index = int({target_layer_index})
target_class_id = int({target_class_id})
imgsz = max(32, int({imgsz}))
conf_threshold = min(1.0, max(0.001, float({conf})))
iou_threshold = min(1.0, max(0.001, float({iou})))
os.makedirs(output_dir, exist_ok=True)

if analysis_mode not in ("aggregate", "bbox", "semantic"):
    raise RuntimeError(f"Unsupported CAM analysis mode: {{analysis_mode}}")
if smoothing_mode not in ("none", "aug", "aug_eigen"):
    raise RuntimeError(f"Unsupported CAM smoothing mode: {{smoothing_mode}}")
if target_layer_index < -3:
    raise RuntimeError(f"Unsupported CAM target layer index: {{target_layer_index}}")


def _select_torch_device(value):
    text = str(value or "").strip().lower()
    if text.startswith("openvino:") or text.startswith("ov:") or text.startswith("intel:"):
        return torch.device("cpu"), "cpu"
    if text in ("", "auto", "cuda", "nv", "nvidia"):
        if torch.cuda.is_available() and torch.cuda.device_count() > 0:
            return torch.device("cuda:0"), "0"
        return torch.device("cpu"), "cpu"
    if text.isdigit():
        index = int(text)
        if torch.cuda.is_available() and index < torch.cuda.device_count():
            return torch.device(f"cuda:{{index}}"), str(index)
        return torch.device("cpu"), "cpu"
    if text.startswith("cuda") and torch.cuda.is_available():
        return torch.device(text), text
    return torch.device("cpu"), "cpu"


def _model_family(path, model=None):
    candidates = [os.path.basename(path)]
    if model is not None:
        candidates.append(str(getattr(model, "yaml_file", "") or ""))
        yaml = getattr(model, "yaml", {{}})
        if isinstance(yaml, dict):
            candidates.append(str(yaml.get("yaml_file", "") or ""))
    name = " ".join(candidates).lower().replace("-", "").replace("_", "")
    if "yolo26" in name:
        return "yolo26"
    if "yolo11" in name:
        return "yolo11"
    if "yolov8" in name or "yolo8" in name:
        return "yolov8"
    sequence = getattr(model, "model", None) if model is not None else None
    modules = list(sequence) if sequence is not None else []
    head = modules[-1] if modules else None
    if bool(getattr(head, "end2end", False)) and int(getattr(head, "reg_max", 0)) == 1:
        return "yolo26"
    return "ultralytics-yolo"


def _resize_source(image, max_side=2048):
    height, width = image.shape[:2]
    longest = max(height, width)
    if longest <= max_side:
        return image
    scale = max_side / float(longest)
    target = (max(1, int(round(width * scale))), max(1, int(round(height * scale))))
    print(
        f"[rustlabel][cam] resize source {{width}}x{{height}} -> {{target[0]}}x{{target[1]}}",
        file=sys.stderr,
    )
    return cv2.resize(image, target, interpolation=cv2.INTER_AREA)


def _letterbox(image, size, stride):
    height, width = image.shape[:2]
    target = max(stride, int(math.ceil(size / stride) * stride))
    scale = min(target / float(width), target / float(height))
    resized_width = max(1, int(round(width * scale)))
    resized_height = max(1, int(round(height * scale)))
    resized = cv2.resize(
        image,
        (resized_width, resized_height),
        interpolation=cv2.INTER_LINEAR if scale > 1 else cv2.INTER_AREA,
    )
    pad_x = target - resized_width
    pad_y = target - resized_height
    left = pad_x // 2
    top = pad_y // 2
    canvas = np.full((target, target, 3), 114, dtype=np.uint8)
    canvas[top : top + resized_height, left : left + resized_width] = resized
    rgb = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB)
    tensor = torch.from_numpy(np.ascontiguousarray(rgb.transpose(2, 0, 1)))
    tensor = tensor.unsqueeze(0).float().div_(255.0)
    return tensor, (left, top, resized_width, resized_height)


def _normalize_boxes_scores(boxes, scores, class_count):
    if boxes.ndim == 2:
        boxes = boxes.unsqueeze(0)
    if scores.ndim == 2:
        scores = scores.unsqueeze(0)
    if boxes.ndim != 3 or scores.ndim != 3:
        raise RuntimeError(
            f"Unsupported YOLO boxes/scores shapes: {{tuple(boxes.shape)}} / {{tuple(scores.shape)}}"
        )
    if boxes.shape[1] == 4 and boxes.shape[-1] != 4:
        boxes = boxes.transpose(1, 2)
    elif boxes.shape[-1] >= 4:
        boxes = boxes[..., :4]
    else:
        raise RuntimeError(f"Cannot normalize YOLO box tensor shape {{tuple(boxes.shape)}}")
    if scores.shape[1] == class_count and scores.shape[-1] != class_count:
        scores = scores.transpose(1, 2)
    elif scores.shape[-1] >= class_count:
        scores = scores[..., :class_count]
    else:
        raise RuntimeError(f"Cannot normalize YOLO score tensor shape {{tuple(scores.shape)}}")
    count = min(boxes.shape[1], scores.shape[1])
    return boxes[:, :count, :], scores[:, :count, :]


def _boxes_scores_from_output(raw, class_count):
    if isinstance(raw, dict):
        for key in ("one2many", "preds", "prediction", "output"):
            if key in raw:
                try:
                    return _boxes_scores_from_output(raw[key], class_count)
                except RuntimeError:
                    pass
        if all(key in raw and torch.is_tensor(raw[key]) for key in ("boxes", "scores")):
            return _normalize_boxes_scores(raw["boxes"], raw["scores"], class_count)
        for value in raw.values():
            try:
                return _boxes_scores_from_output(value, class_count)
            except RuntimeError:
                pass
        raise RuntimeError("No boxes and scores were found in YOLO dictionary output")
    if isinstance(raw, (list, tuple)):
        fallback = None
        for value in raw:
            try:
                boxes, scores = _boxes_scores_from_output(value, class_count)
                if scores.requires_grad:
                    return boxes, scores
                if fallback is None:
                    fallback = (boxes, scores)
            except RuntimeError:
                pass
        if fallback is not None:
            return fallback
        raise RuntimeError("No boxes and scores were found in YOLO sequence output")
    if not torch.is_tensor(raw):
        raise RuntimeError(f"Unsupported YOLO output type: {{type(raw).__name__}}")
    tensor = raw
    if tensor.ndim == 2:
        tensor = tensor.unsqueeze(0)
    if tensor.ndim != 3:
        raise RuntimeError(f"Unsupported YOLO output tensor shape: {{tuple(tensor.shape)}}")
    # Ultralytics detect heads normally return B x (4 + classes + extras) x anchors.
    if tensor.shape[1] >= 4 + class_count and tensor.shape[2] > tensor.shape[1]:
        boxes = tensor[:, :4, :].transpose(1, 2)
        scores = tensor[:, 4 : 4 + class_count, :].transpose(1, 2)
        return boxes, scores
    if tensor.shape[-1] >= 4 + class_count:
        if tensor.shape[-1] == 6:
            possible_ids = tensor[..., 5].detach()
            looks_postprocessed = bool(
                torch.allclose(possible_ids, possible_ids.round(), atol=1e-4)
                and possible_ids.min().item() >= 0
                and possible_ids.max().item() < max(1, class_count)
            )
            if looks_postprocessed:
                return tensor[..., :4], tensor[..., 4:5]
        return tensor[..., :4], tensor[..., 4 : 4 + class_count]
    raise RuntimeError(f"Cannot locate boxes and scores in YOLO output shape {{tuple(tensor.shape)}}")


def _one2many_branch(raw):
    if isinstance(raw, dict):
        branch = raw.get("one2many")
        if isinstance(branch, dict) and all(
            key in branch for key in ("boxes", "scores", "feats")
        ):
            return branch
        for value in raw.values():
            found = _one2many_branch(value)
            if found is not None:
                return found
    elif isinstance(raw, (list, tuple)):
        for value in raw:
            found = _one2many_branch(value)
            if found is not None:
                return found
    return None


def _decoded_candidate_boxes(model, raw, boxes):
    branch = _one2many_branch(raw)
    if branch is None:
        return boxes
    sequence = getattr(model, "model", None)
    modules = list(sequence) if sequence is not None else []
    head = modules[-1] if modules else None
    decode = getattr(head, "_get_decode_boxes", None)
    if not callable(decode):
        raise RuntimeError("YOLO one2many box decoder is unavailable")
    with torch.no_grad():
        decoded = decode(branch)
    if decoded.ndim == 3 and decoded.shape[1] == 4:
        decoded = decoded.transpose(1, 2)
    if decoded.ndim != 3 or decoded.shape[-1] != 4:
        raise RuntimeError(
            f"Unexpected decoded YOLO26 box shape: {{tuple(decoded.shape)}}"
        )
    if decoded.shape[1] != boxes.shape[1]:
        raise RuntimeError(
            f"YOLO26 decoded box count differs from score count: "
            f"{{decoded.shape[1]}} / {{boxes.shape[1]}}"
        )
    return decoded


class _YoloCamModel(nn.Module):
    def __init__(self, model, class_count):
        super().__init__()
        self.model = model
        self.class_count = class_count
        self.last_boxes = None
        self.last_scores = None

    def forward(self, tensor):
        raw = self.model(tensor)
        boxes, scores = _boxes_scores_from_output(raw, self.class_count)
        self.last_boxes = _decoded_candidate_boxes(self.model, raw, boxes).detach()
        self.last_scores = scores.detach()
        return scores.reshape(scores.shape[0], -1)


class _DetectionIndexTarget:
    def __init__(self, score_index):
        self.score_index = int(score_index)

    def __call__(self, output):
        flat = output.reshape(-1)
        if flat.numel() == 0:
            return output.sum()
        safe_index = min(max(0, self.score_index), flat.numel() - 1)
        return flat[safe_index]


class _DetectionIndexesTarget:
    def __init__(self, score_indexes):
        self.score_indexes = [int(index) for index in score_indexes]

    def __call__(self, output):
        flat = output.reshape(-1)
        if flat.numel() == 0 or not self.score_indexes:
            return output.sum()
        indexes = [
            min(max(0, index), flat.numel() - 1)
            for index in self.score_indexes
        ]
        return flat[indexes].sum()


class _DynamicClassScoresTarget:
    def __init__(self, class_ids, class_count):
        self.class_count = max(1, int(class_count))
        self.class_counts = {{}}
        for class_id in class_ids:
            safe_id = min(max(0, int(class_id)), self.class_count - 1)
            self.class_counts[safe_id] = self.class_counts.get(safe_id, 0) + 1

    def __call__(self, output):
        scores = output.reshape(-1, self.class_count)
        if scores.numel() == 0 or not self.class_counts:
            return output.sum()
        total = output.sum() * 0.0
        for class_id, count in self.class_counts.items():
            values = scores[:, class_id]
            top_count = min(max(1, count), values.numel())
            total = total + torch.topk(values, top_count).values.sum()
        return total


def _module_output_tensor(value):
    if torch.is_tensor(value):
        return value
    if isinstance(value, (list, tuple)):
        for item in value:
            tensor = _module_output_tensor(item)
            if tensor is not None:
                return tensor
    if isinstance(value, dict):
        for item in value.values():
            tensor = _module_output_tensor(item)
            if tensor is not None:
                return tensor
    return None


def _resolve_target_layers(core_model, input_tensor):
    sequence = getattr(core_model, "model", None)
    modules = list(sequence) if sequence is not None else []
    if not modules:
        raise RuntimeError("Ultralytics model has no module sequence")
    head = modules[-1]
    head_sources = getattr(head, "f", None)
    indexes = []
    if isinstance(head_sources, int):
        indexes = [head_sources]
    elif isinstance(head_sources, (list, tuple)):
        indexes = [value for value in head_sources if isinstance(value, int)]
    candidates = []
    candidate_names = []
    for index in indexes:
        safe_index = index if index >= 0 else len(modules) + index
        if 0 <= safe_index < len(modules) - 1:
            module = modules[safe_index]
            if module not in candidates:
                candidates.append(module)
                candidate_names.append(f"model.{{safe_index}}:{{module.__class__.__name__}}")

    observed = {{}}
    handles = []
    probe_modules = candidates if candidates else modules[:-1]
    for position, module in enumerate(probe_modules):
        def _capture(_module, _inputs, output, key=position):
            tensor = _module_output_tensor(output)
            if tensor is not None:
                observed[key] = tuple(tensor.shape)
        handles.append(module.register_forward_hook(_capture))
    try:
        with torch.no_grad():
            core_model(input_tensor)
    finally:
        for handle in handles:
            handle.remove()

    if candidates:
        valid_layers = []
        valid_names = []
        for position, (module, name) in enumerate(zip(candidates, candidate_names)):
            shape = observed.get(position)
            if shape is not None and len(shape) == 4 and shape[-2] > 1 and shape[-1] > 1:
                valid_layers.append(module)
                valid_names.append(f"{{name}} {{shape}}")
        if valid_layers:
            return valid_layers, valid_names

    fallback = []
    for position, module in enumerate(probe_modules):
        shape = observed.get(position)
        if shape is not None and len(shape) == 4 and shape[-2] > 1 and shape[-1] > 1:
            fallback.append((position, module, shape))
    if not fallback:
        raise RuntimeError("No spatial feature layer was found before the YOLO detection head")
    position, module, shape = fallback[-1]
    module_index = modules.index(module) if module in modules else position
    return [module], [f"model.{{module_index}}:{{module.__class__.__name__}} {{shape}}"]


def _restore_heatmap(cam, letterbox_info, output_size):
    left, top, resized_width, resized_height = letterbox_info
    cropped = cam[top : top + resized_height, left : left + resized_width]
    if cropped.size == 0:
        raise RuntimeError("CAM crop is empty after removing letterbox padding")
    return cv2.resize(cropped, output_size, interpolation=cv2.INTER_LINEAR)


def _overlay_heatmap(image, heatmap, alpha=0.48):
    normalized = np.clip(heatmap, 0.0, 1.0)
    colored = cv2.applyColorMap(np.uint8(normalized * 255), cv2.COLORMAP_JET)
    return cv2.addWeighted(image, 1.0 - alpha, colored, alpha, 0.0)


def _cpu_numpy(value):
    if value is None:
        return None
    if hasattr(value, "detach"):
        value = value.detach().cpu()
    if hasattr(value, "numpy"):
        value = value.numpy()
    return np.asarray(value)


def _prediction_detections(result, names, limit=12, selected_class_id=-1):
    container = getattr(result, "obb", None)
    is_obb = container is not None and len(container) > 0
    if not is_obb:
        container = getattr(result, "boxes", None)
    if container is None or len(container) == 0:
        return [], 0
    boxes = _cpu_numpy(getattr(container, "xyxy", None))
    classes = _cpu_numpy(getattr(container, "cls", None))
    confidences = _cpu_numpy(getattr(container, "conf", None))
    polygons = _cpu_numpy(getattr(container, "xyxyxyxy", None)) if is_obb else None
    result_masks = getattr(result, "masks", None)
    masks = _cpu_numpy(getattr(result_masks, "data", None)) if result_masks is not None else None
    if boxes is None or classes is None or confidences is None:
        return [], 0
    detections = []
    for index in range(min(len(boxes), len(classes), len(confidences))):
        class_id = int(classes[index])
        name = names.get(class_id, str(class_id)) if isinstance(names, dict) else str(class_id)
        polygon = None
        if polygons is not None and index < len(polygons):
            polygon = np.asarray(polygons[index], dtype=np.float32).reshape(-1, 2)
        semantic_mask = None
        if masks is not None and index < len(masks):
            semantic_mask = cv2.resize(
                np.asarray(masks[index], dtype=np.float32),
                (int(result.orig_shape[1]), int(result.orig_shape[0])),
                interpolation=cv2.INTER_LINEAR,
            ) >= 0.5
        detections.append({{
            "xyxy": np.asarray(boxes[index], dtype=np.float32).reshape(4),
            "polygon": polygon,
            "semanticMask": semantic_mask,
            "classId": class_id,
            "className": str(name),
            "confidence": float(confidences[index]),
        }})
    detections.sort(key=lambda item: item["confidence"], reverse=True)
    if selected_class_id >= 0:
        detections = [
            item for item in detections if item["classId"] == selected_class_id
        ]
    return detections[:limit], len(detections)


def _source_box_to_letterbox(box, source_size, letterbox_info):
    source_width, source_height = source_size
    left, top, resized_width, resized_height = letterbox_info
    scale_x = resized_width / float(max(1, source_width))
    scale_y = resized_height / float(max(1, source_height))
    x1, y1, x2, y2 = [float(value) for value in box]
    return np.asarray([
        x1 * scale_x + left,
        y1 * scale_y + top,
        x2 * scale_x + left,
        y2 * scale_y + top,
    ], dtype=np.float32)


def _xywh_to_xyxy(boxes):
    result = np.empty_like(boxes, dtype=np.float32)
    result[:, 0] = boxes[:, 0] - boxes[:, 2] / 2.0
    result[:, 1] = boxes[:, 1] - boxes[:, 3] / 2.0
    result[:, 2] = boxes[:, 0] + boxes[:, 2] / 2.0
    result[:, 3] = boxes[:, 1] + boxes[:, 3] / 2.0
    return result


def _box_iou_many(box, candidates):
    intersection_x1 = np.maximum(box[0], candidates[:, 0])
    intersection_y1 = np.maximum(box[1], candidates[:, 1])
    intersection_x2 = np.minimum(box[2], candidates[:, 2])
    intersection_y2 = np.minimum(box[3], candidates[:, 3])
    intersection = np.maximum(0.0, intersection_x2 - intersection_x1) * np.maximum(
        0.0, intersection_y2 - intersection_y1
    )
    box_area = max(0.0, box[2] - box[0]) * max(0.0, box[3] - box[1])
    candidate_area = np.maximum(0.0, candidates[:, 2] - candidates[:, 0]) * np.maximum(
        0.0, candidates[:, 3] - candidates[:, 1]
    )
    return intersection / np.maximum(box_area + candidate_area - intersection, 1e-6)


def _match_detection_targets(detections, raw_boxes, raw_scores, source_size, letterbox_info):
    boxes = np.asarray(raw_boxes, dtype=np.float32).reshape(-1, 4)
    scores = np.asarray(raw_scores, dtype=np.float32)
    if scores.ndim != 2 or len(boxes) != len(scores):
        raise RuntimeError(
            f"CAM raw boxes/scores mismatch: {{boxes.shape}} / {{scores.shape}}"
        )
    xywh_boxes = _xywh_to_xyxy(boxes)
    direct_boxes = boxes.copy()
    used = set()
    score_classes = scores.shape[1]
    matched = []
    for detection in detections:
        class_id = min(max(0, detection["classId"]), score_classes - 1)
        target_box = _source_box_to_letterbox(
            detection["xyxy"], source_size, letterbox_info
        )
        xywh_iou = _box_iou_many(target_box, xywh_boxes)
        direct_iou = _box_iou_many(target_box, direct_boxes)
        ious = xywh_iou if float(xywh_iou.max(initial=0.0)) >= float(direct_iou.max(initial=0.0)) else direct_iou
        quality = ious + np.clip(scores[:, class_id], 0.0, None) * 0.05
        if used:
            quality[list(used)] = -1.0
        candidate_index = int(np.argmax(quality))
        if quality[candidate_index] < 0:
            candidate_index = int(np.argmax(ious))
        used.add(candidate_index)
        item = dict(detection)
        item["scoreIndex"] = candidate_index * score_classes + class_id
        item["matchIou"] = float(ious[candidate_index])
        matched.append(item)
    return matched


def _detection_mask(detection, image_size, semantic=False):
    image_width, image_height = image_size
    mask = np.zeros((image_height, image_width), dtype=np.uint8)
    semantic_mask = detection.get("semanticMask")
    if semantic:
        if semantic_mask is None:
            raise RuntimeError("SEG prediction did not expose an instance mask")
        resized = cv2.resize(
            semantic_mask.astype(np.uint8),
            (image_width, image_height),
            interpolation=cv2.INTER_NEAREST,
        )
        return np.where(resized > 0, 255, 0).astype(np.uint8)
    polygon = detection.get("polygon")
    if polygon is not None and len(polygon) >= 3:
        points = np.rint(polygon).astype(np.int32)
        cv2.fillPoly(mask, [points], 255)
        return mask
    x1, y1, x2, y2 = detection["xyxy"]
    left = max(0, min(image_width - 1, int(math.floor(x1))))
    top = max(0, min(image_height - 1, int(math.floor(y1))))
    right = max(left + 1, min(image_width, int(math.ceil(x2))))
    bottom = max(top + 1, min(image_height, int(math.ceil(y2))))
    mask[top:bottom, left:right] = 255
    return mask


def _draw_detection_boxes(image, detections):
    for detection in detections:
        polygon = detection.get("polygon")
        if polygon is not None and len(polygon) >= 3:
            points = np.rint(polygon).astype(np.int32)
            cv2.polylines(image, [points], True, (0, 220, 255), 2, cv2.LINE_AA)
            label_anchor = points[np.argmin(points[:, 1])]
            left, top = int(label_anchor[0]), int(label_anchor[1])
        else:
            x1, y1, x2, y2 = detection["xyxy"]
            left, top = int(round(x1)), int(round(y1))
            cv2.rectangle(
                image,
                (left, top),
                (int(round(x2)), int(round(y2))),
                (0, 220, 255),
                2,
                cv2.LINE_AA,
            )
        text = f"{{detection['className']}} {{detection['confidence']:.2f}}"
        cv2.putText(
            image,
            text,
            (max(0, left), max(14, top - 5)),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.5,
            (0, 220, 255),
            1,
            cv2.LINE_AA,
        )
    return image


def _draw_semantic_contours(image, detections, masks):
    for detection, mask in zip(detections, masks):
        contours, _ = cv2.findContours(
            mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        cv2.drawContours(image, contours, -1, (0, 220, 255), 2, cv2.LINE_AA)
        if contours:
            largest = max(contours, key=cv2.contourArea)
            left, top, _, _ = cv2.boundingRect(largest)
            text = f"{{detection['className']}} {{detection['confidence']:.2f}}"
            cv2.putText(
                image,
                text,
                (max(0, left), max(14, top - 5)),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (0, 220, 255),
                1,
                cv2.LINE_AA,
            )
    return image


started = time.perf_counter()
torch_device, predict_device = _select_torch_device(requested_device)
family = _model_family(model_path)
print(
    f"[rustlabel][cam] start family={{family}} model={{model_path}} device={{torch_device}} imgsz={{imgsz}}",
    file=sys.stderr,
)

source = cv2.imread(input_path, cv2.IMREAD_COLOR)
if source is None:
    raise RuntimeError(f"Cannot read CAM input image: {{input_path}}")
source = _resize_source(source)
height, width = source.shape[:2]

yolo = YOLO(model_path)
family = _model_family(model_path, yolo.model)
task = str(getattr(yolo, "task", "") or getattr(getattr(yolo, "model", None), "task", "") or "").lower()
print(
    f"[rustlabel][cam] resolved family={{family}} task={{task or 'unknown'}}",
    file=sys.stderr,
)
if task not in ("detect", "segment", "obb"):
    raise RuntimeError(f"CAM phase 1 supports detect, segment and obb PT models; model task is '{{task or 'unknown'}}'")
if analysis_mode == "semantic" and task != "segment":
    raise RuntimeError(
        f"Semantic segmentation explanation requires a SEG model; current task is '{{task or 'unknown'}}'"
    )

prediction = yolo.predict(
    source=source,
    save=False,
    imgsz=imgsz,
    conf=conf_threshold,
    iou=iou_threshold,
    device=predict_device,
    verbose=False,
)[0]
prediction_names = getattr(prediction, "names", None) or getattr(yolo, "names", {{}}) or {{}}
if not isinstance(prediction_names, dict):
    prediction_names = {{index: str(value) for index, value in enumerate(prediction_names)}}
selected_class_id = target_class_id if analysis_mode == "bbox" else -1
if selected_class_id >= 0 and selected_class_id not in prediction_names:
    raise RuntimeError(f"Selected class id {{selected_class_id}} is not present in model.names")
detections, detected_box_count = _prediction_detections(
    prediction,
    {{int(key): str(value) for key, value in prediction_names.items()}},
    selected_class_id=selected_class_id,
)
target_class_name = (
    str(prediction_names.get(selected_class_id, selected_class_id))
    if selected_class_id >= 0
    else ""
)
original_detect = prediction.plot()
original_path = os.path.join(output_dir, "original_detect.jpg")
if not cv2.imwrite(original_path, original_detect, [cv2.IMWRITE_JPEG_QUALITY, 92]):
    raise RuntimeError(f"Failed to save CAM detection preview: {{original_path}}")
if not detections and analysis_mode != "aggregate":
    class_detail = f" for class '{{target_class_name}}'" if target_class_name else ""
    raise RuntimeError(
        f"No predictions{{class_detail}} met confidence threshold {{conf_threshold:.2f}}"
    )

# YOLO26 switches a model used by the high-level predictor to its detached
# one-to-one inference branch. Reload a clean PT graph for gradient analysis.
del prediction
del original_detect
del yolo
gc.collect()
if torch.cuda.is_available():
    torch.cuda.empty_cache()
yolo = YOLO(model_path)
core_model = yolo.model
core_model.to(torch_device)
core_model.eval()
class_names = getattr(yolo, "names", {{}}) or getattr(core_model, "names", {{}}) or {{}}
class_count = max(1, len(class_names))
stride_value = getattr(core_model, "stride", 32)
if torch.is_tensor(stride_value):
    stride = max(1, int(stride_value.max().detach().cpu().item()))
elif isinstance(stride_value, (list, tuple)):
    stride = max(1, int(max(stride_value)))
else:
    stride = max(1, int(stride_value or 32))
input_tensor, letterbox_info = _letterbox(source, imgsz, stride)
input_tensor = input_tensor.to(torch_device)
input_tensor.requires_grad_(True)
torch.set_grad_enabled(True)

all_target_layers, available_target_layer_names = _resolve_target_layers(
    core_model, input_tensor
)
if target_layer_index >= 0 and target_layer_index >= len(all_target_layers):
    raise RuntimeError(
        f"CAM target layer index {{target_layer_index}} is unavailable; "
        f"model exposes {{len(all_target_layers)}} target layer(s)"
    )
if target_layer_index == -3:
    target_layer_groups = [(-1, all_target_layers, "Auto")] + [
        (index, [layer], available_target_layer_names[index])
        for index, layer in enumerate(all_target_layers)
    ]
    target_layer_names = list(available_target_layer_names)
elif target_layer_index == -2:
    target_layer_groups = [
        (index, [layer], available_target_layer_names[index])
        for index, layer in enumerate(all_target_layers)
    ]
    target_layer_names = list(available_target_layer_names)
elif target_layer_index == -1:
    target_layer_groups = [(-1, all_target_layers, "auto")]
    target_layer_names = list(available_target_layer_names)
else:
    target_layer_groups = [(
        target_layer_index,
        [all_target_layers[target_layer_index]],
        available_target_layer_names[target_layer_index],
    )]
    target_layer_names = [available_target_layer_names[target_layer_index]]
cam_model = _YoloCamModel(core_model, class_count).to(torch_device).eval()
probe_scores = cam_model(input_tensor)
if cam_model.last_boxes is None or cam_model.last_scores is None:
    raise RuntimeError("CAM model did not expose raw boxes and scores")
matched_detections = (
    _match_detection_targets(
        detections,
        cam_model.last_boxes[0].cpu().numpy(),
        cam_model.last_scores[0].cpu().numpy(),
        (width, height),
        letterbox_info,
    )
    if detections
    else []
)
raw_target_indexes = [item["scoreIndex"] for item in matched_detections]
raw_target_class_ids = [item["classId"] for item in matched_detections]
if not raw_target_indexes:
    flattened_scores = cam_model.last_scores[0].reshape(-1)
    if flattened_scores.numel() == 0:
        raise RuntimeError("CAM model raw class scores are empty")
    best_raw_index = int(torch.argmax(flattened_scores).item())
    best_class_id = best_raw_index % class_count
    best_score = float(flattened_scores[best_raw_index].item())
    raw_target_indexes = [best_raw_index]
    raw_target_class_ids = [best_class_id]
    best_class_name = (
        str(class_names.get(best_class_id, best_class_id))
        if isinstance(class_names, dict)
        else str(best_class_id)
    )
    print(
        f"[rustlabel][cam] no postprocessed detections at threshold "
        f"{{conf_threshold:.2f}}; aggregate target uses raw class "
        f"{{best_class_id}} ({{best_class_name}}) score={{best_score:.6f}}",
        file=sys.stderr,
    )
del probe_scores
input_tensor.grad = None
core_model.zero_grad(set_to_none=True)
region_masks = [] if analysis_mode == "aggregate" else [
    _detection_mask(
        detection,
        (width, height),
        semantic=analysis_mode == "semantic",
    )
    for detection in matched_detections
]
union_mask = (
    np.full((height, width), 255, dtype=np.uint8)
    if analysis_mode == "aggregate"
    else np.maximum.reduce(region_masks)
)
methods = [
    ("EigenCAM", "eigen_cam.jpg", EigenCAM),
    ("Grad-CAM", "grad_cam.jpg", GradCAM),
    ("Grad-CAM++", "grad_cam_plus_plus.jpg", GradCAMPlusPlus),
    ("XGrad-CAM", "xgrad_cam.jpg", XGradCAM),
    ("ScoreCAM", "score_cam.jpg", ScoreCAM),
]
outputs = [{{
    "id": "original_detect",
    "label": "original_detect",
    "path": os.path.abspath(original_path),
    "targetLayerIndex": -1,
    "targetLayerName": "",
}}]
aug_smooth = smoothing_mode in ("aug", "aug_eigen")
eigen_smooth = smoothing_mode == "aug_eigen"
smooth_label = {{
    "none": "",
    "aug": " · aug_smooth",
    "aug_eigen": " · aug+eigen smooth",
}}[smoothing_mode]
fixed_target = _DetectionIndexesTarget(
    raw_target_indexes
)
dynamic_target = _DynamicClassScoresTarget(
    raw_target_class_ids, class_count
)

for label, file_name, cam_type in methods:
    for render_layer_index, render_target_layers, render_layer_name in target_layer_groups:
        method_started = time.perf_counter()
        try:
            print(
                f"[rustlabel][cam] rendering method={{label}} mode={{analysis_mode}} "
                f"smoothing={{smoothing_mode}} layer={{render_layer_index}} "
                f"targets={{len(matched_detections)}}",
                file=sys.stderr,
            )
            core_model.zero_grad(set_to_none=True)
            input_tensor.grad = None
            with cam_type(model=cam_model, target_layers=render_target_layers) as cam:
                target = dynamic_target if aug_smooth or cam_type is ScoreCAM else fixed_target
                grayscale = cam(
                    input_tensor=input_tensor,
                    targets=[target],
                    aug_smooth=aug_smooth,
                    eigen_smooth=eigen_smooth,
                )[0]
                restored = _restore_heatmap(grayscale, letterbox_info, (width, height))
                composite = restored * (union_mask.astype(np.float32) / 255.0)
            blended = _overlay_heatmap(source, composite)
            overlay = source.copy()
            active = union_mask > 0
            overlay[active] = blended[active]
            if analysis_mode == "bbox":
                overlay = _draw_detection_boxes(overlay, matched_detections)
            elif analysis_mode == "semantic":
                overlay = _draw_semantic_contours(
                    overlay, matched_detections, region_masks
                )
            stem, extension = os.path.splitext(file_name)
            layer_suffix = (
                f"layer_{{render_layer_index}}"
                if render_layer_index >= 0
                else "auto"
            )
            output_name = f"{{stem}}_{{layer_suffix}}_{{smoothing_mode}}{{extension}}"
            output_path = os.path.join(output_dir, output_name)
            if not cv2.imwrite(output_path, overlay, [cv2.IMWRITE_JPEG_QUALITY, 92]):
                raise RuntimeError(f"Failed to save CAM output: {{output_path}}")
            layer_label = f" · {{render_layer_name}}"
            outputs.append({{
                "id": stem,
                "label": label + smooth_label + layer_label,
                "path": os.path.abspath(output_path),
                "durationMs": int(round((time.perf_counter() - method_started) * 1000)),
                "targetLayerIndex": int(render_layer_index),
                "targetLayerName": str(render_layer_name),
            }})
        finally:
            core_model.zero_grad(set_to_none=True)
            gc.collect()
            if torch.cuda.is_available():
                torch.cuda.empty_cache()

result = {{
    "ok": True,
    "family": family,
    "task": task,
    "device": str(torch_device),
    "ultralyticsVersion": str(getattr(ultralytics, "__version__", "unknown")),
    "targetLayers": target_layer_names,
    "availableTargetLayers": available_target_layer_names,
    "targetLayerIndex": int(target_layer_index),
    "mode": analysis_mode,
    "smoothing": smoothing_mode,
    "targetClassId": int(selected_class_id),
    "targetClassName": target_class_name,
    "threshold": float(conf_threshold),
    "detectedBoxes": int(detected_box_count),
    "analyzedBoxes": int(len(matched_detections)),
    "minimumMatchIou": float(
        min((item["matchIou"] for item in matched_detections), default=0.0)
    ),
    "outputs": outputs,
    "durationMs": int(round((time.perf_counter() - started) * 1000)),
}}
print(json.dumps(result, ensure_ascii=False))
"###,
        model_path = detecting_mod::python_string_literal(&model_path.to_string_lossy()),
        input_path = detecting_mod::python_string_literal(&input_path.to_string_lossy()),
        output_dir = detecting_mod::python_string_literal(&output_dir.to_string_lossy()),
        device = detecting_mod::python_string_literal(&req.device),
        mode = detecting_mod::python_string_literal(&req.mode),
        smoothing = detecting_mod::python_string_literal(&req.smoothing),
        target_layer_index = req.target_layer_index,
        target_class_id = req.target_class_id,
        imgsz = req.imgsz.max(32),
        conf = req.conf_threshold.clamp(0.001, 1.0),
        iou = req.iou_threshold.clamp(0.001, 1.0),
    );

    detecting_mod::run_python_json_script(&python, &script, None)
}
