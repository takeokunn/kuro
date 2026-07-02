#[allow(unused_imports)]
use super::tests_support::{fill_cell, fill_rows, row_char, row_is_blank};
#[allow(unused_imports)]
use super::*;
use crate::grid::screen::DEFAULT_SCROLLBACK_MAX;
#[allow(unused_imports)]
use crate::types::cell::{CellWidth, SgrAttributes};
use crate::Color;
use crate::Screen;
use proptest::prelude::*;

#[path = "tests_cases/alt_screen.rs"]
mod alt_screen;
#[path = "tests_cases/basics.rs"]
mod basics;
#[path = "tests_cases/combining.rs"]
mod combining;
#[path = "tests_cases/pbt.rs"]
mod pbt;
#[path = "tests_cases/resize.rs"]
mod resize;
#[path = "tests_cases/scrollback.rs"]
mod scrollback;
#[path = "tests_cases/viewport.rs"]
mod viewport;
#[path = "tests_cases/wide_chars.rs"]
mod wide_chars;

#[path = "init.rs"]
mod init;
#[path = "insert_delete.rs"]
mod insert_delete;
#[path = "properties.rs"]
mod properties;
#[path = "unicode.rs"]
mod unicode;
