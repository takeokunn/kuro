//! Unit test modules with 1:1 file correspondence to src/ structure.
//!
//! Each submodule mirrors the source tree:
//!   src/tests/unit/types/color.rs  ↔  src/types/color.rs
//!   src/tests/unit/grid/line.rs    ↔  src/grid/line.rs
//!   etc.
//!
//! All modules have access to `pub(crate)` items through the crate's
//! `#[cfg(test)]` module hierarchy.

pub(super) mod ffi;
pub(super) mod grid;
pub(super) mod parser;
pub(super) mod types;
