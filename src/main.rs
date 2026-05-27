use std::path::PathBuf;
use std::process::{Command, ExitCode};

const FLUTTER_PROJECT_DIR: &str = "flutter";
const FLUTTER_DEVICE: &str = "windows";

/// Development launcher for the desktop UI.
///
/// RustRover runs this binary when the user presses Run. The actual application
/// UI is the Flutter desktop app, so this launcher first builds the Rust FFI
/// library and then delegates to `flutter run`.
fn main() -> ExitCode {
    let project_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let flutter_dir = project_dir.join(FLUTTER_PROJECT_DIR);

    if !flutter_dir.join("pubspec.yaml").exists() {
        eprintln!("Flutter project not found at {}", flutter_dir.display());
        return ExitCode::FAILURE;
    }

    if !run(
        Command::new("cargo")
            .arg("build")
            .arg("--release")
            .current_dir(&project_dir),
        "cargo build --release",
    ) {
        return ExitCode::FAILURE;
    }

    if !run(
        Command::new(flutter_command())
            .arg("run")
            .arg("-d")
            .arg(FLUTTER_DEVICE)
            .current_dir(&flutter_dir),
        "flutter run -d windows",
    ) {
        return ExitCode::FAILURE;
    }

    ExitCode::SUCCESS
}

fn flutter_command() -> &'static str {
    if cfg!(windows) {
        "flutter.bat"
    } else {
        "flutter"
    }
}

/// Runs a child process and reports a compact, user-readable failure.
fn run(command: &mut Command, label: &str) -> bool {
    println!("Running {label}...");

    match command.status() {
        Ok(status) if status.success() => true,
        Ok(status) => {
            eprintln!("{label} failed with status {status}");
            false
        }
        Err(error) => {
            eprintln!("Failed to start {label}: {error}");
            false
        }
    }
}
