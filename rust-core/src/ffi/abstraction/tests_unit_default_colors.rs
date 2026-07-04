#[path = "tests_unit_default_colors_support.rs"]
mod support;

pub(crate) use super::make_session;

#[path = "tests_unit_default_colors_basic.rs"]
mod basic;

#[path = "tests_unit_default_colors_scrollback.rs"]
mod scrollback;

#[path = "tests_unit_default_colors_cursor.rs"]
mod cursor;

#[path = "tests_unit_default_colors_misc.rs"]
mod misc;
