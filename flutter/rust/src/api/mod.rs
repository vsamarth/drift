use std::sync::LazyLock;

use tokio::runtime::Runtime;

pub mod device;
pub mod lan;
pub mod preview;
pub mod receiver;
pub mod sender;
pub mod transfer;
pub mod simple;

pub(crate) static RUNTIME: LazyLock<Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("tokio runtime")
});
