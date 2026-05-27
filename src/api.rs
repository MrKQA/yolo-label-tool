use flutter_rust_bridge::frb;

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
