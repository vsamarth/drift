pub mod api;
mod frb_generated;

// Re-export so the generated `frb_generated.rs` can reference it via `crate::*`.
pub use drift_core::protocol::DeviceType;
