#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    // Ensures RUNTIME and static setup are touched when the Dart side initializes Rust.
}

#[flutter_rust_bridge::frb(sync)]
pub fn greet(name: String) -> String {
    format!("Hello, {name}")
}
