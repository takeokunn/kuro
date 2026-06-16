#[allow(unused_imports)]
use super::*;
use crate::Color;
use crate::Screen;
use crate::grid::screen::DEFAULT_SCROLLBACK_MAX;
#[allow(unused_imports)]
use crate::types::cell::{CellWidth, SgrAttributes};
use proptest::prelude::*;
#[allow(unused_imports)]
use super::tests_support::{fill_cell, fill_rows, row_char, row_is_blank};

#[path = "tests_cases/basics.rs"]
mod basics;
#[path = "tests_cases/scrollback.rs"]
mod scrollback;
#[path = "tests_cases/alt_screen.rs"]
mod alt_screen;
#[path = "tests_cases/resize.rs"]
mod resize;
#[path = "tests_cases/wide_chars.rs"]
mod wide_chars;
#[path = "tests_cases/viewport.rs"]
mod viewport;
#[path = "tests_cases/combining.rs"]
mod combining;
#[path = "tests_cases/pbt.rs"]
mod pbt;

#[path = "unicode.rs"]
mod unicode;
#[path = "properties.rs"]
mod properties;
#[path = "insert_delete.rs"]
mod insert_delete;
#[path = "init.rs"]
mod init;
