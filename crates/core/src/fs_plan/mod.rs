//! Local filesystem planning for transfers.
//!
//! - [`transfer_path`] — validation and normalization of logical transfer paths.
//! - [`preview`] — quick scan of user-selected paths (counts and sizes).
//! - [`prepare`] — async walk, hashing, and [`OfferManifest`](crate::rendezvous::OfferManifest) for sending.
//! - [`receive`] — map an offer manifest to on-disk destinations before accepting.

pub mod prepare;
pub mod preview;
pub mod receive;
pub mod transfer_path;

#[cfg(test)]
mod test_support;

pub use prepare::{PreparedFile, PreparedFiles, prepare_files};
pub use preview::{
    SelectedPathKind, SelectedPathPreview, SelectionPreview, inspect_selected_paths,
};
pub use receive::{
    ExpectedFile, build_expected_files, ensure_destination_available, resolve_transfer_destination,
};
pub use transfer_path::validate_transfer_path;
