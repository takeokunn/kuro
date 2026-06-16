//! Unit tests for FFI abstraction: session management, encode delegates, sync output.

#[macro_use]
#[path = "tests_unit_support.rs"]
mod tests_unit_support;

pub(crate) use tests_unit_support::make_session;

use super::global::{
    attach_session, detach_session, list_sessions, shutdown_session, with_session,
    TERMINAL_SESSIONS,
};
pub(super) use super::session::{SessionState, TerminalSession};
pub(super) use crate::error::KuroError;
pub(super) use crate::ffi::error::StateError;
pub(super) use crate::types::cell::SgrAttributes;
pub(super) use crate::types::color::Color;

#[path = "tests_unit_cases.rs"]
mod cases;

#[path = "tests_unit_color_scheme.rs"]
mod color_scheme;

#[path = "tests_unit_dec_accessors.rs"]
mod dec_accessors;

#[path = "tests_unit_dec_accessors_ext.rs"]
mod dec_accessors_ext;

#[path = "tests_unit_default_colors.rs"]
mod default_colors;

#[path = "tests_unit_dirty_binary_support.rs"]
mod dirty_binary_support;

#[path = "tests_unit_dirty_binary.rs"]
mod dirty_binary;

#[path = "tests_unit_dirty_lines_support.rs"]
mod dirty_lines_support;

#[path = "tests_unit_dirty_lines.rs"]
mod dirty_lines;

#[path = "tests_unit_dirty_viewport_support.rs"]
mod dirty_viewport_support;

#[path = "tests_unit_dirty_viewport.rs"]
mod dirty_viewport;

#[path = "tests_unit_dirty_viewport2.rs"]
mod dirty_viewport2;

#[path = "tests_unit_isolation.rs"]
mod isolation;

#[path = "tests_unit_osc.rs"]
mod osc;

#[path = "tests_unit_scroll.rs"]
mod scroll;

#[path = "tests_unit_session.rs"]
mod session;
