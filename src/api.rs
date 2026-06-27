use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::slice;
use std::sync::Mutex;
use sysinfo::System;

#[path = "training.rs"]
pub mod training_mod;

#[path = "IniPython.rs"]
pub mod ini_python;

#[path = "detecting.rs"]
pub mod detecting_mod;

#[path = "database.rs"]
pub mod database_mod;

#[path = "collaboration.rs"]
pub mod collaboration_mod;

use training_mod::{TrainingConfig, TrainingProgress};

static RESOURCE_MONITOR_SYSTEM: Lazy<Mutex<System>> = Lazy::new(|| Mutex::new(System::new()));

/// Smoke-test function exposed to Flutter through flutter_rust_bridge.
#[frb]
pub fn rust_greeting(name: String) -> String {
    format!("Hello from Rust, {name}!")
}

/// Annotation modes planned for the first version of the labeling tool.
#[frb]
pub fn supported_annotation_modes() -> Vec<String> {
    ["hbb", "obb", "seg"]
        .into_iter()
        .map(String::from)
        .collect()
}

/// Result returned after FFmpeg extracts still images from one or more videos.
#[derive(Debug, Clone)]
pub struct FrameExtractionResult {
    pub ffmpeg_path: String,
    pub output_dir: String,
    pub frame_count: u32,
}

/// Metadata needed by the Flutter video browser/player.
#[derive(Debug, Clone)]
pub struct VideoPlaybackInfo {
    pub width: u32,
    pub height: u32,
    pub duration_seconds: f64,
    pub fps: f64,
    pub frame_count: u32,
    pub decoder_label: String,
}

/// One decoded video frame returned as PNG bytes.
#[derive(Debug, Clone)]
pub struct DecodedVideoFrame {
    pub timestamp_seconds: f64,
    pub png_bytes: Vec<u8>,
    pub decoder_label: String,
}

#[derive(Debug, Clone)]
struct HardwareDecoder {
    label: String,
    ffmpeg_args: Vec<String>,
}

#[derive(Debug, Clone)]
struct NvidiaGpuInfo {
    index: u32,
    name: String,
    free_memory_mb: u32,
}

/// FFI byte buffer used by the Flutter video player fallback.
#[frb(ignore)]
#[repr(C)]
pub struct RustLabelByteBuffer {
    pub ptr: *mut u8,
    pub len: usize,
    pub cap: usize,
}

unsafe impl Send for RustLabelByteBuffer {}
unsafe impl Sync for RustLabelByteBuffer {}

/// Check whether an FFmpeg executable can be found by the backend.
#[frb]
pub fn ffmpeg_path() -> Option<String> {
    find_ffmpeg().map(|path| path.to_string_lossy().into_owned())
}

/// Read video metadata through Rust + FFprobe for the browse/player page.
#[frb]
pub fn video_playback_info(video_path: String) -> Result<VideoPlaybackInfo, String> {
    let video = ensure_existing_video(&video_path)?;
    let ffmpeg = find_ffmpeg().ok_or_else(|| {
        "FFmpeg was not found. Set FFMPEG_PATH or add ffmpeg to PATH.".to_string()
    })?;
    let ffprobe = find_ffprobe(&ffmpeg).ok_or_else(|| {
        "FFprobe was not found. Set FFPROBE_PATH or place ffprobe beside ffmpeg.".to_string()
    })?;
    let decoder = detect_best_hardware_decoder(&ffmpeg);
    let mut info = probe_video_playback_info(&ffprobe, &video)?;
    info.decoder_label = decoder.label;
    Ok(info)
}

/// Decode one video frame through Rust + FFmpeg.
///
/// The returned bytes are PNG data, so Flutter can display them with
/// `Image.memory` without doing native pixel-format conversion on the Dart side.
#[frb]
pub fn decode_video_frame(
    video_path: String,
    timestamp_seconds: f64,
    max_width: u32,
) -> Result<DecodedVideoFrame, String> {
    let video = ensure_existing_video(&video_path)?;
    let ffmpeg = find_ffmpeg().ok_or_else(|| {
        "FFmpeg was not found. Set FFMPEG_PATH or add ffmpeg to PATH.".to_string()
    })?;
    let decoder = detect_best_hardware_decoder(&ffmpeg);
    let timestamp = timestamp_seconds.max(0.0);

    match decode_video_frame_with_args(&ffmpeg, &video, timestamp, max_width, &decoder.ffmpeg_args)
    {
        Ok(png_bytes) => Ok(DecodedVideoFrame {
            timestamp_seconds: timestamp,
            png_bytes,
            decoder_label: decoder.label,
        }),
        Err(hardware_error) if !decoder.ffmpeg_args.is_empty() => {
            let png_bytes =
                decode_video_frame_with_args(&ffmpeg, &video, timestamp, max_width, &[]).map_err(
                    |cpu_error| {
                        format!(
                    "Hardware decode failed:\n{hardware_error}\n\nCPU decode failed:\n{cpu_error}"
                )
                    },
                )?;
            Ok(DecodedVideoFrame {
                timestamp_seconds: timestamp,
                png_bytes,
                decoder_label: "CPU decode".to_string(),
            })
        }
        Err(error) => Err(error),
    }
}

/// C ABI: return video metadata JSON for Flutter's manual FFI player.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_video_info_json(
    path_ptr: *const u8,
    path_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(path_ptr, path_len)
        .and_then(video_playback_info)
        .map(video_playback_info_json)
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: decode one timestamp into PNG bytes for Flutter's manual FFI player.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_decode_video_frame_png(
    path_ptr: *const u8,
    path_len: usize,
    timestamp_seconds: f64,
    max_width: u32,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(path_ptr, path_len)
        .and_then(|path| decode_video_frame(path, timestamp_seconds, max_width))
        .map(|frame| frame.png_bytes)
        .unwrap_or_default();
    vec_into_ffi_buffer(result)
}

/// C ABI: run YOLO detection from a JSON request for Flutter's manual FFI path.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_detect_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| detect_from_json_request(&request))
        .map(detect_result_json)
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: inspect a YOLO model and return its `model.task`.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_detect_model_task_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| detect_model_task_from_json_request(&request))
        .map(detect_model_task_result_json)
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: inspect a YOLO model and return class names for AI-assisted labeling.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_ai_model_classes_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| ai_model_classes_from_json_request(&request))
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: run YOLO on one image and return raw HBB predictions.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_ai_annotate_image_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| ai_annotate_image_from_json_request(&request))
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: run YOLO on multiple images in one Python process for AI-assisted labeling.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_ai_annotate_images_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| ai_annotate_images_from_json_request(&request))
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: warm up the embedded Python runtime used by training.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_preload_yolo_python_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let python_path = required_json_string(&request, "pythonPath")?;
            training_mod::preload_yolo_python(&python_path)
                .map(|message| format!("{{\"ok\":true,\"message\":\"{}\"}}", json_escape(&message)))
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: return the current training log tail for live terminal display.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_training_log_tail_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let max_chars = json_u32_field(&request, "maxChars").unwrap_or(30 * 1024) as usize;
            training_mod::training_log_tail(max_chars).map(|(path, text)| {
                format!(
                    "{{\"ok\":true,\"path\":\"{}\",\"text\":\"{}\"}}",
                    json_escape(&path),
                    json_escape(&text)
                )
            })
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: return host/GPU resource usage for the training chart panel.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_training_resource_usage_json(
    _request_ptr: *const u8,
    _request_len: usize,
) -> RustLabelByteBuffer {
    let result = training_resource_usage_json().unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: stop active Python-backed training/detection work before app exit.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_shutdown_python_json(
    _request_ptr: *const u8,
    _request_len: usize,
) -> RustLabelByteBuffer {
    let stop_message = training_mod::shutdown_training(5_000)
        .unwrap_or_else(|error| format!("training stop failed: {error}"));
    let killed_children = detecting_mod::shutdown_python_children();
    let python_message = ini_python::shutdown_python_runtime()
        .map(|_| "python runtime workers stopped".to_string())
        .unwrap_or_else(|error| format!("python runtime worker stop failed: {error}"));
    let result = format!(
        "{{\"ok\":true,\"message\":\"{}\",\"pythonMessage\":\"{}\",\"killedChildren\":{}}}",
        json_escape(&stop_message),
        json_escape(&python_message),
        killed_children
    );
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: save the current label workspace into AnnotationConfig.db.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_save_snapshot_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let payload = required_json_string(&request, "payload")?;
            database_mod::save_snapshot(&payload)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: reconcile the current image list and load annotations from AnnotationConfig.db.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_load_snapshot_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let payload = required_json_string(&request, "payload")?;
            database_mod::load_snapshot(&payload)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: save one application config JSON value into AnnotationConfig.db.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_save_config_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let key = required_json_string(&request, "key")?;
            let value = required_json_string(&request, "value")?;
            database_mod::save_config_value(&key, &value)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: load one application config JSON value from AnnotationConfig.db.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_load_config_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let key = required_json_string(&request, "key")?;
            database_mod::load_config_value(&key)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: delete one application config value from AnnotationConfig.db.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_delete_config_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let key = required_json_string(&request, "key")?;
            database_mod::delete_config_value(&key)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: append application log lines into AnnotationConfig.db.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_append_logs_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let lines = required_json_string(&request, "lines")?;
            database_mod::append_log_lines(&lines)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: list application log dates stored in AnnotationConfig.db.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_log_dates_json(
    _request_ptr: *const u8,
    _request_len: usize,
) -> RustLabelByteBuffer {
    let result = database_mod::log_dates().unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: read application logs for one date from AnnotationConfig.db.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_read_logs_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let date = required_json_string(&request, "date")?;
            database_mod::read_logs_for_date(&date)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: delete application logs in a closed date range from AnnotationConfig.db.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_delete_logs_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let start_date = required_json_string(&request, "startDate")?;
            let end_date = required_json_string(&request, "endDate")?;
            database_mod::delete_logs_by_date_range(&start_date, &end_date)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: summarize AnnotationConfig.db tables and config keys.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_overview_json(
    _request_ptr: *const u8,
    _request_len: usize,
) -> RustLabelByteBuffer {
    let result = database_mod::database_overview().unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: query a whitelisted AnnotationConfig.db table for the database manager.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_table_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let table = required_json_string(&request, "table")?;
            let project_id = required_json_string(&request, "projectId").unwrap_or_default();
            let image_id = required_json_string(&request, "imageId").unwrap_or_default();
            let limit = required_json_string(&request, "limit").unwrap_or_default();
            let offset = required_json_string(&request, "offset").unwrap_or_default();
            database_mod::database_table(&table, &project_id, &image_id, &limit, &offset)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: run one read-only SQL query against AnnotationConfig.db.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_db_sql_query_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let sql = required_json_string(&request, "sql")?;
            database_mod::database_sql_query(&sql)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: list date-based training terminal logs stored under the project logs folder.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_training_log_dates_json(
    _request_ptr: *const u8,
    _request_len: usize,
) -> RustLabelByteBuffer {
    let result = training_mod::training_log_dates_json().unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: read one date-based training terminal log.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_read_training_log_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let date = required_json_string(&request, "date")?;
            training_mod::read_training_log_for_date_json(&date)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: delete date-based training terminal logs in a closed range.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_delete_training_logs_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| {
            let start_date = required_json_string(&request, "startDate")?;
            let end_date = required_json_string(&request, "endDate")?;
            training_mod::delete_training_logs_by_date_range_json(&start_date, &end_date)
        })
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: dispatch one collaboration-network command.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_collab_command_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .and_then(|request| collaboration_mod::command_json(&request))
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: poll pending collaboration-network events.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_collab_poll_json(
    request_ptr: *const u8,
    request_len: usize,
) -> RustLabelByteBuffer {
    let result = string_from_ffi(request_ptr, request_len)
        .map(|request| json_u32_field(&request, "maxEvents").unwrap_or(50) as usize)
        .and_then(collaboration_mod::poll_events_json)
        .unwrap_or_else(error_json);
    vec_into_ffi_buffer(result.into_bytes())
}

/// C ABI: free buffers returned by `rust_label_*` FFI functions.
#[frb(ignore)]
#[no_mangle]
pub unsafe extern "C" fn rust_label_free_byte_buffer(buffer: RustLabelByteBuffer) {
    if buffer.ptr.is_null() || buffer.len == 0 {
        return;
    }
    drop(Vec::from_raw_parts(buffer.ptr, buffer.len, buffer.cap));
}

/// Extract frames from videos with FFmpeg.
///
/// `frame_interval` means "keep one frame every N input frames". A value of 1
/// exports every frame. When `lossless` is true, PNG files are generated;
/// otherwise JPEG files are generated with an FFmpeg qscale derived from
/// `image_quality`.
#[frb]
pub fn extract_video_frames(
    video_paths: Vec<String>,
    output_root: String,
    folder_name: String,
    frame_interval: u32,
    image_quality: u8,
    lossless: bool,
) -> Result<FrameExtractionResult, String> {
    if video_paths.is_empty() {
        return Err("No video files selected".to_string());
    }

    let ffmpeg = find_ffmpeg().ok_or_else(|| {
        "FFmpeg was not found. Set FFMPEG_PATH or add ffmpeg to PATH.".to_string()
    })?;
    let output_dir = sanitize_output_dir(&output_root, &folder_name)?;
    fs::create_dir_all(&output_dir).map_err(|error| {
        format!(
            "Failed to create output directory {}: {error}",
            output_dir.display()
        )
    })?;

    let interval = frame_interval.max(1);
    let mut frame_count = 0_u32;
    for (video_index, video_path) in video_paths.iter().enumerate() {
        let video = PathBuf::from(video_path);
        if !video.exists() {
            return Err(format!("Video file does not exist: {video_path}"));
        }

        let stem = video
            .file_stem()
            .and_then(|value| value.to_str())
            .map(sanitize_file_stem)
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| format!("video_{:03}", video_index + 1));
        let extension = if lossless { "png" } else { "jpg" };
        let output_pattern = output_dir.join(format!("{stem}_%06d.{extension}"));
        let before_count = count_images_with_prefix(&output_dir, &stem, extension)?;

        let mut command = Command::new(&ffmpeg);
        command
            .arg("-hide_banner")
            .arg("-y")
            .arg("-i")
            .arg(&video)
            .arg("-vf")
            .arg(format!("select=not(mod(n\\,{interval}))"))
            .arg("-vsync")
            .arg("0");
        if lossless {
            command.arg("-compression_level").arg("0");
        } else {
            command
                .arg("-q:v")
                .arg(jpeg_quality_to_qscale(image_quality));
        }
        command.arg(&output_pattern);

        let output = command.output().map_err(|error| {
            format!(
                "Failed to start FFmpeg at {}: {error}",
                ffmpeg.to_string_lossy()
            )
        })?;
        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!(
                "FFmpeg failed for {}:\n{}",
                video.display(),
                stderr.trim()
            ));
        }

        let after_count = count_images_with_prefix(&output_dir, &stem, extension)?;
        frame_count += after_count.saturating_sub(before_count);
    }

    Ok(FrameExtractionResult {
        ffmpeg_path: ffmpeg.to_string_lossy().into_owned(),
        output_dir: output_dir.to_string_lossy().into_owned(),
        frame_count,
    })
}

fn find_ffmpeg() -> Option<PathBuf> {
    env::var_os("FFMPEG_PATH")
        .map(PathBuf::from)
        .filter(|path| path.exists())
        .or_else(find_ffmpeg_near_project)
        .or_else(find_ffmpeg_on_path)
}

fn find_ffprobe(ffmpeg: &Path) -> Option<PathBuf> {
    env::var_os("FFPROBE_PATH")
        .map(PathBuf::from)
        .filter(|path| path.exists())
        .or_else(|| find_ffprobe_next_to_ffmpeg(ffmpeg))
        .or_else(find_ffprobe_near_project)
        .or_else(find_ffprobe_on_path)
}

fn find_ffprobe_next_to_ffmpeg(ffmpeg: &Path) -> Option<PathBuf> {
    let parent = ffmpeg.parent()?;
    if parent.as_os_str().is_empty() {
        return None;
    }
    let candidate = parent.join(if cfg!(windows) {
        "ffprobe.exe"
    } else {
        "ffprobe"
    });
    candidate.exists().then_some(candidate)
}

fn find_ffmpeg_near_project() -> Option<PathBuf> {
    let current = env::current_dir().ok()?;
    let candidates = [
        current.join("ffmpeg").join("bin").join("ffmpeg.exe"),
        current
            .join("tools")
            .join("ffmpeg")
            .join("bin")
            .join("ffmpeg.exe"),
        current
            .parent()
            .unwrap_or(&current)
            .join("ffmpeg")
            .join("bin")
            .join("ffmpeg.exe"),
    ];
    candidates.into_iter().find(|path| path.exists())
}

fn find_ffprobe_near_project() -> Option<PathBuf> {
    let current = env::current_dir().ok()?;
    let candidates = [
        current.join("ffmpeg").join("bin").join("ffprobe.exe"),
        current
            .join("tools")
            .join("ffmpeg")
            .join("bin")
            .join("ffprobe.exe"),
        current
            .parent()
            .unwrap_or(&current)
            .join("ffmpeg")
            .join("bin")
            .join("ffprobe.exe"),
    ];
    candidates.into_iter().find(|path| path.exists())
}

fn find_ffmpeg_on_path() -> Option<PathBuf> {
    Command::new("ffmpeg")
        .arg("-version")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|_| PathBuf::from("ffmpeg"))
}

fn find_ffprobe_on_path() -> Option<PathBuf> {
    Command::new("ffprobe")
        .arg("-version")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .map(|_| PathBuf::from("ffprobe"))
}

fn ensure_existing_video(video_path: &str) -> Result<PathBuf, String> {
    let video = PathBuf::from(video_path.trim());
    if video_path.trim().is_empty() {
        return Err("Video path is empty".to_string());
    }
    if !video.exists() {
        return Err(format!("Video file does not exist: {video_path}"));
    }
    Ok(video)
}

fn probe_video_playback_info(ffprobe: &Path, video: &Path) -> Result<VideoPlaybackInfo, String> {
    let output = Command::new(ffprobe)
        .arg("-v")
        .arg("error")
        .arg("-select_streams")
        .arg("v:0")
        .arg("-show_entries")
        .arg(
            "stream=width,height,avg_frame_rate,r_frame_rate,duration,duration_ts,time_base,nb_frames:format=duration",
        )
        .arg("-of")
        .arg("default=noprint_wrappers=0")
        .arg(video)
        .output()
        .map_err(|error| format!("Failed to start FFprobe: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "FFprobe failed for {}:\n{}",
            video.display(),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    let mut width = 0_u32;
    let mut height = 0_u32;
    let mut fps = 0.0_f64;
    let mut duration = 0.0_f64;
    let mut format_duration = 0.0_f64;
    let mut duration_ts = 0.0_f64;
    let mut time_base = 0.0_f64;
    let mut frame_count = 0_u32;
    let mut section = "";

    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let line = line.trim();
        match line {
            "[STREAM]" => {
                section = "stream";
                continue;
            }
            "[FORMAT]" => {
                section = "format";
                continue;
            }
            "[/STREAM]" | "[/FORMAT]" => {
                section = "";
                continue;
            }
            _ => {}
        }
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let value = value.trim();
        match (section, key.trim()) {
            (_, "width") => width = value.parse::<u32>().unwrap_or(0),
            (_, "height") => height = value.parse::<u32>().unwrap_or(0),
            (_, "avg_frame_rate") if fps <= 0.0 => {
                fps = parse_frame_rate(value).unwrap_or(0.0);
            }
            (_, "r_frame_rate") if fps <= 0.0 => {
                fps = parse_frame_rate(value).unwrap_or(0.0);
            }
            ("stream", "duration") if duration <= 0.0 => {
                duration = parse_positive_f64(value).unwrap_or(0.0);
            }
            ("format", "duration") if format_duration <= 0.0 => {
                format_duration = parse_positive_f64(value).unwrap_or(0.0);
            }
            (_, "duration_ts") if duration_ts <= 0.0 => {
                duration_ts = parse_positive_f64(value).unwrap_or(0.0);
            }
            (_, "time_base") if time_base <= 0.0 => {
                time_base = parse_frame_rate(value).unwrap_or(0.0);
            }
            (_, "nb_frames") => frame_count = value.parse::<u32>().unwrap_or(0),
            _ => {}
        }
    }

    if width == 0 || height == 0 {
        return Err(format!(
            "Could not read video dimensions for {}",
            video.display()
        ));
    }
    if duration <= 0.0 && duration_ts > 0.0 && time_base > 0.0 {
        duration = duration_ts * time_base;
    }
    if duration <= 0.0 && format_duration > 0.0 {
        duration = format_duration;
    }
    if frame_count == 0 && duration > 0.0 && fps > 0.0 {
        frame_count = (duration * fps).round().max(1.0) as u32;
    }

    Ok(VideoPlaybackInfo {
        width,
        height,
        duration_seconds: duration,
        fps: if fps > 0.0 { fps } else { 25.0 },
        frame_count,
        decoder_label: "CPU decode".to_string(),
    })
}

fn decode_video_frame_with_args(
    ffmpeg: &Path,
    video: &Path,
    timestamp_seconds: f64,
    max_width: u32,
    decoder_args: &[String],
) -> Result<Vec<u8>, String> {
    let mut command = Command::new(ffmpeg);
    command
        .arg("-hide_banner")
        .arg("-loglevel")
        .arg("error")
        .arg("-y");
    for arg in decoder_args {
        command.arg(arg);
    }
    command
        .arg("-ss")
        .arg(format!("{:.3}", timestamp_seconds.max(0.0)))
        .arg("-i")
        .arg(video)
        .arg("-frames:v")
        .arg("1");
    if max_width > 0 {
        command
            .arg("-vf")
            .arg(format!("scale=min(iw\\,{max_width}):-1"));
    }
    command
        .arg("-f")
        .arg("image2pipe")
        .arg("-vcodec")
        .arg("png")
        .arg("-");

    let output = command
        .output()
        .map_err(|error| format!("Failed to start FFmpeg: {error}"))?;
    if !output.status.success() {
        return Err(String::from_utf8_lossy(&output.stderr).trim().to_string());
    }
    if output.stdout.is_empty() {
        return Err("FFmpeg returned an empty frame".to_string());
    }
    Ok(output.stdout)
}

fn detect_best_hardware_decoder(ffmpeg: &Path) -> HardwareDecoder {
    let hwaccels = ffmpeg_hwaccels(ffmpeg);
    if hwaccels.iter().any(|value| value == "cuda") {
        if let Some(gpu) = detect_best_nvidia_gpu() {
            return HardwareDecoder {
                label: format!(
                    "CUDA GPU {} - {} ({} MB)",
                    gpu.index, gpu.name, gpu.free_memory_mb
                ),
                ffmpeg_args: vec![
                    "-hwaccel".to_string(),
                    "cuda".to_string(),
                    "-hwaccel_device".to_string(),
                    gpu.index.to_string(),
                ],
            };
        }
    }

    let has_intel_gpu = has_intel_gpu();
    if has_intel_gpu && hwaccels.iter().any(|value| value == "qsv") {
        return HardwareDecoder {
            label: "Intel Quick Sync Video (QSV)".to_string(),
            ffmpeg_args: vec!["-hwaccel".to_string(), "qsv".to_string()],
        };
    }
    if has_intel_gpu && hwaccels.iter().any(|value| value == "d3d11va") {
        return HardwareDecoder {
            label: "Intel D3D11VA".to_string(),
            ffmpeg_args: vec!["-hwaccel".to_string(), "d3d11va".to_string()],
        };
    }
    if hwaccels.iter().any(|value| value == "d3d11va") {
        return HardwareDecoder {
            label: "D3D11VA".to_string(),
            ffmpeg_args: vec!["-hwaccel".to_string(), "d3d11va".to_string()],
        };
    }

    HardwareDecoder {
        label: "CPU decode".to_string(),
        ffmpeg_args: Vec::new(),
    }
}

fn ffmpeg_hwaccels(ffmpeg: &Path) -> Vec<String> {
    let Ok(output) = Command::new(ffmpeg)
        .arg("-hide_banner")
        .arg("-hwaccels")
        .output()
    else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }
    String::from_utf8_lossy(&output.stdout)
        .split_whitespace()
        .map(|value| value.trim().to_ascii_lowercase())
        .filter(|value| !value.is_empty() && value != "hardware" && value != "acceleration")
        .collect()
}

fn detect_best_nvidia_gpu() -> Option<NvidiaGpuInfo> {
    let output = Command::new("nvidia-smi")
        .arg("--query-gpu=index,name,memory.free")
        .arg("--format=csv,noheader,nounits")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }

    String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter_map(parse_nvidia_gpu_line)
        .max_by_key(|gpu| gpu.free_memory_mb)
}

fn parse_nvidia_gpu_line(line: &str) -> Option<NvidiaGpuInfo> {
    let parts = line.split(',').map(str::trim).collect::<Vec<_>>();
    if parts.len() < 3 {
        return None;
    }
    let index = parts.first()?.parse::<u32>().ok()?;
    let free_memory_mb = parts.last()?.parse::<u32>().ok()?;
    let name = parts[1..parts.len() - 1].join(", ");
    Some(NvidiaGpuInfo {
        index,
        name: if name.is_empty() {
            "NVIDIA GPU".to_string()
        } else {
            name
        },
        free_memory_mb,
    })
}

fn has_intel_gpu() -> bool {
    let Ok(output) = Command::new("powershell")
        .arg("-NoProfile")
        .arg("-Command")
        .arg(r#"Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }"#)
        .output()
    else {
        return false;
    };
    output.status.success()
        && String::from_utf8_lossy(&output.stdout)
            .to_ascii_lowercase()
            .contains("intel")
}

fn parse_frame_rate(value: &str) -> Option<f64> {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed == "0/0" || trimmed.eq_ignore_ascii_case("n/a") {
        return None;
    }
    if let Some((numerator, denominator)) = trimmed.split_once('/') {
        let numerator = numerator.parse::<f64>().ok()?;
        let denominator = denominator.parse::<f64>().ok()?;
        if denominator == 0.0 {
            return None;
        }
        return Some(numerator / denominator);
    }
    parse_positive_f64(trimmed)
}

fn parse_positive_f64(value: &str) -> Option<f64> {
    let parsed = value.trim().parse::<f64>().ok()?;
    (parsed.is_finite() && parsed > 0.0).then_some(parsed)
}

fn training_resource_usage_json() -> Result<String, String> {
    let (cpu_percent, ram_percent) = {
        let mut system = RESOURCE_MONITOR_SYSTEM
            .lock()
            .map_err(|_| "resource monitor lock failed".to_string())?;
        system.refresh_cpu();
        system.refresh_memory();
        let cpu_percent = system.global_cpu_info().cpu_usage() as f64;
        let total_memory = system.total_memory() as f64;
        let used_memory = system.used_memory() as f64;
        let ram_percent = if total_memory > 0.0 {
            used_memory / total_memory * 100.0
        } else {
            0.0
        };
        (cpu_percent, ram_percent)
    };

    let gpu = query_nvidia_resource_usage();
    Ok(format!(
        concat!(
            "{{\"ok\":true,",
            "\"cpuPercent\":{},",
            "\"ramPercent\":{},",
            "\"gpuPercent\":{},",
            "\"vramPercent\":{}",
            "}}"
        ),
        finite_json_number(clamp_percent(cpu_percent)),
        finite_json_number(clamp_percent(ram_percent)),
        optional_json_number(gpu.and_then(|value| value.gpu_percent)),
        optional_json_number(gpu.and_then(|value| value.vram_percent)),
    ))
}

#[derive(Debug, Clone, Copy)]
struct NvidiaResourceUsage {
    gpu_percent: Option<f64>,
    vram_percent: Option<f64>,
}

fn query_nvidia_resource_usage() -> Option<NvidiaResourceUsage> {
    let output = Command::new("nvidia-smi")
        .arg("--query-gpu=utilization.gpu,memory.used,memory.total")
        .arg("--format=csv,noheader,nounits")
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }

    let mut gpu_percent: Option<f64> = None;
    let mut used_vram = 0.0;
    let mut total_vram = 0.0;
    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let parts = line.split(',').map(str::trim).collect::<Vec<_>>();
        if parts.len() < 3 {
            continue;
        }
        if let Some(value) = parse_percent_number(parts[0]) {
            gpu_percent = Some(gpu_percent.map_or(value, |current| current.max(value)));
        }
        let used = parse_positive_or_zero_f64(parts[1]).unwrap_or(0.0);
        let total = parse_positive_or_zero_f64(parts[2]).unwrap_or(0.0);
        if total > 0.0 {
            used_vram += used;
            total_vram += total;
        }
    }

    let vram_percent = if total_vram > 0.0 {
        Some(used_vram / total_vram * 100.0)
    } else {
        None
    };
    Some(NvidiaResourceUsage {
        gpu_percent: gpu_percent.map(clamp_percent),
        vram_percent: vram_percent.map(clamp_percent),
    })
}

fn parse_percent_number(value: &str) -> Option<f64> {
    let parsed = value
        .trim()
        .trim_end_matches('%')
        .trim()
        .parse::<f64>()
        .ok()?;
    parsed.is_finite().then_some(clamp_percent(parsed))
}

fn parse_positive_or_zero_f64(value: &str) -> Option<f64> {
    let parsed = value.trim().parse::<f64>().ok()?;
    (parsed.is_finite() && parsed >= 0.0).then_some(parsed)
}

fn clamp_percent(value: f64) -> f64 {
    if value.is_finite() {
        value.clamp(0.0, 100.0)
    } else {
        0.0
    }
}

unsafe fn string_from_ffi(path_ptr: *const u8, path_len: usize) -> Result<String, String> {
    if path_ptr.is_null() && path_len > 0 {
        return Err("Path pointer is null".to_string());
    }
    let bytes = slice::from_raw_parts(path_ptr, path_len);
    String::from_utf8(bytes.to_vec()).map_err(|error| format!("Path is not UTF-8: {error}"))
}

fn vec_into_ffi_buffer(mut bytes: Vec<u8>) -> RustLabelByteBuffer {
    if bytes.is_empty() {
        return RustLabelByteBuffer {
            ptr: std::ptr::null_mut(),
            len: 0,
            cap: 0,
        };
    }
    let buffer = RustLabelByteBuffer {
        ptr: bytes.as_mut_ptr(),
        len: bytes.len(),
        cap: bytes.capacity(),
    };
    std::mem::forget(bytes);
    buffer
}

fn video_playback_info_json(info: VideoPlaybackInfo) -> String {
    format!(
        "{{\"ok\":true,\"width\":{},\"height\":{},\"durationSeconds\":{},\"fps\":{},\"frameCount\":{},\"decoderLabel\":\"{}\"}}",
        info.width,
        info.height,
        finite_json_number(info.duration_seconds),
        finite_json_number(info.fps),
        info.frame_count,
        json_escape(&info.decoder_label),
    )
}

fn detect_result_json(result: detecting_mod::DetectResult) -> String {
    if result.ok {
        format!(
            "{{\"ok\":true,\"outputPath\":\"{}\",\"labelCount\":{}}}",
            json_escape(&result.output_path),
            result.label_count,
        )
    } else {
        error_json(
            result
                .error
                .unwrap_or_else(|| "Detection failed".to_string()),
        )
    }
}

fn detect_model_task_result_json(result: detecting_mod::DetectModelTaskResult) -> String {
    if result.ok {
        format!(
            "{{\"ok\":true,\"task\":\"{}\",\"folder\":\"{}\"}}",
            json_escape(&result.task),
            json_escape(&result.folder),
        )
    } else {
        error_json(
            result
                .error
                .unwrap_or_else(|| "Failed to inspect model task".to_string()),
        )
    }
}

fn detect_model_task_from_json_request(
    request: &str,
) -> Result<detecting_mod::DetectModelTaskResult, String> {
    let python_path = required_json_string(request, "pythonPath")?;
    let model_path = required_json_string(request, "modelPath")?;
    Ok(detecting_mod::detect_model_task(&python_path, &model_path))
}

fn ai_model_classes_from_json_request(request: &str) -> Result<String, String> {
    let python_path = required_json_string(request, "pythonPath")?;
    let model_path = required_json_string(request, "modelPath")?;
    detecting_mod::ai_model_classes_json(&python_path, &model_path)
}

fn ai_annotate_image_from_json_request(request: &str) -> Result<String, String> {
    let req = detecting_mod::AiAnnotateImageRequest {
        python_path: required_json_string(request, "pythonPath")?,
        model_path: required_json_string(request, "modelPath")?,
        input_path: required_json_string(request, "inputPath")?,
        class_ids_csv: json_string_field(request, "classIdsCsv").unwrap_or_default(),
        conf_threshold: json_f64_field(request, "confThreshold").unwrap_or(0.25),
        iou_threshold: json_f64_field(request, "iouThreshold").unwrap_or(0.45),
        imgsz: json_u32_field(request, "imgsz").unwrap_or(640),
        device: json_string_field(request, "device").unwrap_or_else(|| "auto".to_string()),
    };
    detecting_mod::ai_annotate_image_json(&req)
}

fn ai_annotate_images_from_json_request(request: &str) -> Result<String, String> {
    let req = detecting_mod::AiAnnotateBatchRequest {
        python_path: required_json_string(request, "pythonPath")?,
        model_path: required_json_string(request, "modelPath")?,
        input_paths_text: required_json_string(request, "inputPathsText")?,
        class_ids_csv: json_string_field(request, "classIdsCsv").unwrap_or_default(),
        conf_threshold: json_f64_field(request, "confThreshold").unwrap_or(0.25),
        iou_threshold: json_f64_field(request, "iouThreshold").unwrap_or(0.45),
        imgsz: json_u32_field(request, "imgsz").unwrap_or(640),
        device: json_string_field(request, "device").unwrap_or_else(|| "auto".to_string()),
    };
    detecting_mod::ai_annotate_images_json(&req)
}

fn detect_from_json_request(request: &str) -> Result<detecting_mod::DetectResult, String> {
    let mode = json_string_field(request, "mode").unwrap_or_else(|| "image".to_string());
    let python_path = required_json_string(request, "pythonPath")?;
    let model_path = required_json_string(request, "modelPath")?;
    let input_path = required_json_string(request, "inputPath")?;
    let output_dir = required_json_string(request, "outputDir")?;
    let output_name = json_string_field(request, "outputName").unwrap_or_else(|| {
        let extension = if mode.eq_ignore_ascii_case("video") {
            "mp4"
        } else {
            "jpg"
        };
        format!("result.{extension}")
    });
    let conf_threshold = json_f64_field(request, "confThreshold").unwrap_or(0.25);
    let iou_threshold = json_f64_field(request, "iouThreshold").unwrap_or(0.45);
    let imgsz = json_u32_field(request, "imgsz").unwrap_or(640);
    let device = json_string_field(request, "device").unwrap_or_else(|| "auto".to_string());
    let preview_frames = json_bool_field(request, "previewFrames").unwrap_or(false);
    let cancel_path = json_string_field(request, "cancelPath").unwrap_or_default();
    let start_frame = json_u32_field(request, "startFrame").unwrap_or(0);

    if mode.eq_ignore_ascii_case("video") {
        let ffmpeg_path = match json_string_field(request, "ffmpegPath") {
            Some(path) if !path.trim().is_empty() => path,
            _ => find_ffmpeg()
                .ok_or_else(|| {
                    "FFmpeg was not found. Set FFMPEG_PATH or add ffmpeg to PATH.".to_string()
                })?
                .to_string_lossy()
                .into_owned(),
        };
        let req = detecting_mod::DetectVideoRequest {
            python_path,
            model_path,
            input_path,
            output_dir,
            output_name,
            conf_threshold,
            iou_threshold,
            imgsz,
            device,
            ffmpeg_path,
            preview_frames,
            cancel_path,
            start_frame,
        };
        Ok(detecting_mod::detect_video(&req))
    } else {
        let req = detecting_mod::DetectImageRequest {
            python_path,
            model_path,
            input_path,
            output_dir,
            output_name,
            conf_threshold,
            iou_threshold,
            imgsz,
            device,
        };
        Ok(detecting_mod::detect_image(&req))
    }
}

fn required_json_string(request: &str, key: &str) -> Result<String, String> {
    json_string_field(request, key)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| format!("Missing {key}"))
}

fn error_json(error: String) -> String {
    format!(
        "{{\"ok\":false,\"error\":\"{}\"}}",
        json_escape(error.trim())
    )
}

fn json_string_field(input: &str, key: &str) -> Option<String> {
    let mut index = json_value_start(input, key)?;
    let chars: Vec<char> = input.chars().collect();
    if chars.get(index) != Some(&'"') {
        return None;
    }
    index += 1;
    let mut value = String::new();
    while index < chars.len() {
        match chars[index] {
            '"' => return Some(value),
            '\\' => {
                index += 1;
                let escaped = *chars.get(index)?;
                match escaped {
                    '"' => value.push('"'),
                    '\\' => value.push('\\'),
                    '/' => value.push('/'),
                    'b' => value.push('\u{0008}'),
                    'f' => value.push('\u{000c}'),
                    'n' => value.push('\n'),
                    'r' => value.push('\r'),
                    't' => value.push('\t'),
                    'u' => {
                        let hex: String = chars.get(index + 1..index + 5)?.iter().collect();
                        let code = u32::from_str_radix(&hex, 16).ok()?;
                        value.push(char::from_u32(code)?);
                        index += 4;
                    }
                    other => value.push(other),
                }
            }
            ch => value.push(ch),
        }
        index += 1;
    }
    None
}

fn json_f64_field(input: &str, key: &str) -> Option<f64> {
    json_raw_scalar(input, key)?.parse::<f64>().ok()
}

fn json_u32_field(input: &str, key: &str) -> Option<u32> {
    let value = json_raw_scalar(input, key)?;
    value.parse::<u32>().ok().or_else(|| {
        value
            .parse::<f64>()
            .ok()
            .filter(|number| number.is_finite() && *number >= 0.0)
            .map(|number| number.round() as u32)
    })
}

fn json_bool_field(input: &str, key: &str) -> Option<bool> {
    match json_raw_scalar(input, key)?.to_ascii_lowercase().as_str() {
        "true" => Some(true),
        "false" => Some(false),
        _ => None,
    }
}

fn json_raw_scalar(input: &str, key: &str) -> Option<String> {
    let start = json_value_start(input, key)?;
    let chars: Vec<char> = input.chars().collect();
    let mut end = start;
    while end < chars.len() && !matches!(chars[end], ',' | '}' | ']') {
        end += 1;
    }
    let value: String = chars[start..end].iter().collect();
    Some(value.trim().trim_matches('"').to_string())
}

fn json_value_start(input: &str, key: &str) -> Option<usize> {
    let needle = format!("\"{}\"", key);
    let key_byte_index = input.find(&needle)?;
    let after_key = key_byte_index + needle.len();
    let colon_byte_offset = input[after_key..].find(':')?;
    let value_byte_index = after_key + colon_byte_offset + 1;
    let char_index = input[..value_byte_index].chars().count();
    let chars: Vec<char> = input.chars().collect();
    let mut index = char_index;
    while index < chars.len() && chars[index].is_whitespace() {
        index += 1;
    }
    Some(index)
}

fn finite_json_number(value: f64) -> String {
    if value.is_finite() {
        format!("{value:.6}")
    } else {
        "0".to_string()
    }
}

fn optional_json_number(value: Option<f64>) -> String {
    match value {
        Some(value) if value.is_finite() => finite_json_number(value),
        _ => "null".to_string(),
    }
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

fn sanitize_output_dir(output_root: &str, folder_name: &str) -> Result<PathBuf, String> {
    let root = PathBuf::from(output_root.trim());
    if output_root.trim().is_empty() {
        return Err("Output root is empty".to_string());
    }
    let folder = sanitize_file_stem(folder_name);
    if folder.is_empty() {
        return Err("Folder name is empty".to_string());
    }
    Ok(root.join(folder))
}

fn sanitize_file_stem(value: &str) -> String {
    value
        .chars()
        .map(|ch| match ch {
            '<' | '>' | ':' | '"' | '/' | '\\' | '|' | '?' | '*' => '_',
            _ if ch.is_control() => '_',
            _ => ch,
        })
        .collect::<String>()
        .trim()
        .trim_matches('.')
        .to_string()
}

fn jpeg_quality_to_qscale(image_quality: u8) -> String {
    let quality = image_quality.clamp(1, 100) as u16;
    let qscale = 31 - ((quality - 1) * 29 / 99);
    qscale.clamp(2, 31).to_string()
}

/// Start a YOLO training run through the embedded PyO3 Python runtime.
///
/// Runs Ultralytics `model.train(...)` on a background Rust thread.
/// Returns the experiment run directory path on success.
#[frb]
pub fn start_yolo_training(
    python_path: String,
    model_path: String,
    data_yaml_path: String,
    project_dir: String,
    experiment_name: String,
    epochs: u32,
    imgsz: u32,
    batch: String,
    device: String,
    lr0: f64,
    momentum: f64,
    patience: u32,
    hsv_h: f64,
    hsv_s: f64,
    hsv_v: f64,
    translate: f64,
    scale: f64,
    shear: f64,
    flipud: f64,
    fliplr: f64,
    degrees: f64,
    perspective: f64,
    bgr: f64,
    mosaic: f64,
    mixup: f64,
    cutmix: f64,
    copy_paste: f64,
    copy_paste_mode: String,
    auto_augment: String,
    erasing: f64,
    workers: u32,
    amp: bool,
    resume: bool,
    cls_pw: f64,
) -> Result<String, String> {
    let config = TrainingConfig {
        python_path,
        model_path,
        data_yaml_path,
        project_dir,
        experiment_name,
        epochs,
        imgsz,
        batch,
        device,
        lr0,
        momentum,
        patience,
        hsv_h,
        hsv_s,
        hsv_v,
        translate,
        scale,
        shear,
        flipud,
        fliplr,
        degrees,
        perspective,
        bgr,
        mosaic,
        mixup,
        cutmix,
        copy_paste,
        copy_paste_mode,
        auto_augment,
        erasing,
        workers,
        amp,
        resume,
        cls_pw,
    };
    training_mod::start_training(config)
}

/// Poll training progress from the results.csv written by Ultralytics.
#[frb]
pub fn poll_yolo_training_progress() -> Option<TrainingProgress> {
    training_mod::poll_training_progress()
}

/// Stop the active YOLO training process.
#[frb]
pub fn stop_yolo_training() -> Result<String, String> {
    training_mod::stop_training()
}

/// Run YOLO detection on a single image, save the annotated result.
#[frb]
pub fn detect_image(
    python_path: String,
    model_path: String,
    input_path: String,
    output_dir: String,
    output_name: String,
    conf_threshold: f64,
    iou_threshold: f64,
    imgsz: u32,
    device: String,
) -> detecting_mod::DetectResult {
    let req = detecting_mod::DetectImageRequest {
        python_path,
        model_path,
        input_path,
        output_dir,
        output_name,
        conf_threshold,
        iou_threshold,
        imgsz,
        device,
    };
    detecting_mod::detect_image(&req)
}

/// Run YOLO detection on a video, encode output with FFmpeg h264.
#[frb]
pub fn detect_video(
    python_path: String,
    model_path: String,
    input_path: String,
    output_dir: String,
    output_name: String,
    conf_threshold: f64,
    iou_threshold: f64,
    imgsz: u32,
    device: String,
    ffmpeg_path: String,
) -> detecting_mod::DetectResult {
    let req = detecting_mod::DetectVideoRequest {
        python_path,
        model_path,
        input_path,
        ffmpeg_path,
        output_dir,
        output_name,
        conf_threshold,
        iou_threshold,
        imgsz,
        device,
        preview_frames: false,
        cancel_path: String::new(),
        start_frame: 0,
    };
    detecting_mod::detect_video(&req)
}

fn count_images_with_prefix(
    output_dir: &Path,
    prefix: &str,
    extension: &str,
) -> Result<u32, String> {
    let mut count = 0_u32;
    let extension = extension.to_ascii_lowercase();
    let prefix = format!("{prefix}_");
    for entry in fs::read_dir(output_dir)
        .map_err(|error| format!("Failed to read {}: {error}", output_dir.display()))?
    {
        let entry = entry.map_err(|error| error.to_string())?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
            continue;
        };
        let Some(ext) = path.extension().and_then(|value| value.to_str()) else {
            continue;
        };
        if name.starts_with(&prefix) && ext.eq_ignore_ascii_case(&extension) {
            count += 1;
        }
    }
    Ok(count)
}
