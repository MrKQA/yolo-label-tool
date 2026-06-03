use flutter_rust_bridge::frb;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::slice;

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
#[repr(C)]
pub struct RustLabelByteBuffer {
    pub ptr: *mut u8,
    pub len: usize,
    pub cap: usize,
}

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

/// C ABI: free buffers returned by `rust_label_*` FFI functions.
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
        .arg("stream=width,height,avg_frame_rate,r_frame_rate,duration,nb_frames:format=duration")
        .arg("-of")
        .arg("default=noprint_wrappers=1")
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
    let mut frame_count = 0_u32;

    for line in String::from_utf8_lossy(&output.stdout).lines() {
        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let value = value.trim();
        match key.trim() {
            "width" => width = value.parse::<u32>().unwrap_or(0),
            "height" => height = value.parse::<u32>().unwrap_or(0),
            "avg_frame_rate" if fps <= 0.0 => {
                fps = parse_frame_rate(value).unwrap_or(0.0);
            }
            "r_frame_rate" if fps <= 0.0 => {
                fps = parse_frame_rate(value).unwrap_or(0.0);
            }
            "duration" if duration <= 0.0 => {
                duration = parse_positive_f64(value).unwrap_or(0.0);
            }
            "nb_frames" => frame_count = value.parse::<u32>().unwrap_or(0),
            _ => {}
        }
    }

    if width == 0 || height == 0 {
        return Err(format!(
            "Could not read video dimensions for {}",
            video.display()
        ));
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

fn error_json(error: String) -> String {
    format!(
        "{{\"ok\":false,\"error\":\"{}\"}}",
        json_escape(error.trim())
    )
}

fn finite_json_number(value: f64) -> String {
    if value.is_finite() {
        format!("{value:.6}")
    } else {
        "0".to_string()
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
