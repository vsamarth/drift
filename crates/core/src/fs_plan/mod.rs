//! Local filesystem planning for transfers.
//!
//! - [`preview`] — quick scan of user-selected paths (counts and sizes).
//! - [`prepare`] — async walk, hashing, and [`OfferManifest`](crate::rendezvous::OfferManifest) for sending.

pub mod prepare;
pub mod preview;

#[cfg(test)]
mod test_support;

pub use prepare::{PreparedFile, PreparedFiles, prepare_files};
pub use preview::{
    SelectedPathKind, SelectedPathPreview, SelectionPreview, inspect_selected_paths,
};
