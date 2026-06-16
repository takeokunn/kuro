//! Property-based and example-based tests for `csi` parsing.
//!
//! Module under test: `parser/csi.rs`
//! Tier: T2 — `ProptestConfig::with_cases(500)`
#![expect(
    clippy::cast_possible_truncation,
    reason = "test coordinate casts: rows/cols are terminal dimensions (≤ 65535); usize→u16 is safe"
)]

use super::*;

#[macro_use]
#[path = "csi/tests_support.rs"]
mod tests_support;

#[path = "csi/tests_cases.rs"]
mod tests_cases;

#[path = "csi/cursor_line_clamping.rs"]
mod cursor_line_clamping;

#[path = "csi/device_status.rs"]
mod device_status;

#[path = "csi/pbt.rs"]
mod pbt;

#[path = "csi/xtwinops.rs"]
mod xtwinops;
