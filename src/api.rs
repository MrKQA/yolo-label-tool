use flutter_rust_bridge::frb;

#[frb]
pub fn rust_greeting(name: String) -> String {
    format!("Hello from Rust, {name}!")
}

#[frb]
pub fn supported_annotation_modes() -> Vec<String> {
    ["hbb", "obb", "seg"]
        .into_iter()
        .map(String::from)
        .collect()
}

