pub const ALPN: &[u8] = b"drift/transfer/v1";

pub(crate) mod error;
pub(crate) mod message;
pub(crate) mod receive;
pub(crate) mod send;
pub(crate) mod wire;

pub use error::ProtocolError;
pub use message::{DeviceType, Identity, TransferRole, PROTOCOL_VERSION};
