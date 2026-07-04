use super::*;
use crate::types::cell::{CellWidth, SgrFlags};
use crate::types::{Color, NamedColor, SgrAttributes};
use proptest::prelude::*;

#[path = "minimal_terminal.rs"]
mod minimal_terminal;

#[path = "character_fill.rs"]
mod character_fill;

#[path = "ext_cases/ed_el.rs"]
mod ed_el;

#[path = "ext_cases/deccara.rs"]
mod deccara;

#[path = "ext_cases/xtcolors.rs"]
mod xtcolors;

#[path = "ext_cases/deccra.rs"]
mod deccra;
