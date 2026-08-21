use std::process::Command;

fn main() {
    let script = r#"
        tell application "System Events"
            set prevApp to item 1 of (get name of processes whose frontmost is true)
        end tell
        return prevApp
    "#;
    let output = Command::new("osascript").arg("-e").arg(script).output().unwrap();
    println!("Frontmost: {}", String::from_utf8_lossy(&output.stdout));
}
