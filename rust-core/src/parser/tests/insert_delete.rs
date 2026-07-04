//! Property-based and example-based tests for `insert_delete` parsing.
//!
//! Module under test: `parser/insert_delete.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;

#[path = "insert_delete_support.rs"]
mod support;

#[path = "insert_delete_cases.rs"]
mod cases;
