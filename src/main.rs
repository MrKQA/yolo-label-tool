use std::path::PathBuf;
use std::process::{Command, ExitCode};

fn main() -> ExitCode {
    let project_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let flutter_dir = project_dir.join("flutter");

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

    let flutter_command = if cfg!(windows) {
        "flutter.bat"
    } else {
        "flutter"
    };

    if !run(
        Command::new(flutter_command)
            .arg("run")
            .arg("-d")
            .arg("windows")
            .current_dir(&flutter_dir),
        "flutter run -d windows",
    ) {
        return ExitCode::FAILURE;
    }

    ExitCode::SUCCESS
}

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
