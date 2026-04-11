#[flutter_rust_bridge::frb(sync)]
pub fn random_device_name() -> String {
    drift_core::util::random_device_name()
}
