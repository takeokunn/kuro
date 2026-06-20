//! Property-based and example-based tests for `kitty` parsing.
//!
//! Module under test: `parser/kitty.rs`
//! Tier: T3 — `ProptestConfig::with_cases(256)`

#[macro_use]
#[path = "kitty/support.rs"]
mod support;

#[path = "kitty/params.rs"]
mod params;

#[path = "kitty/params_extra.rs"]
mod params_extra;

#[path = "kitty/png.rs"]
mod png_cases;

#[path = "kitty/png_extra.rs"]
mod png_extra_cases;

#[path = "kitty/frame.rs"]
mod frame;
