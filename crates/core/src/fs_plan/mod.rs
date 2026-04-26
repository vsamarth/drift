//! Local filesystem planning for transfers.
//!
//! - [`preview`] — selection preview derived from the sender import walk.

pub mod conflict;
pub mod error;
pub mod preview;

#[cfg(test)]
mod test_support;

pub use conflict::ConflictPolicy;
pub use error::FsPlanError;
pub use preview::{
    SelectedPathKind, SelectedPathPreview, SelectionPreview, inspect_selected_paths,
};
