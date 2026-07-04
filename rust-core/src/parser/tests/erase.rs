//! Property-based and example-based tests for `erase` parsing.
//!
//! Module under test: `parser/erase.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

use super::*;

#[macro_use]
#[path = "erase/tests_support.rs"]
mod tests_support;

#[path = "erase/tests_cases.rs"]
mod tests_cases;

#[path = "erase/ext.rs"]
mod ext;
