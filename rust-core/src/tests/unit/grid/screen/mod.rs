pub(super) mod alternate;
pub(super) mod cursor;
pub(super) mod dirty;
pub(super) mod edit;
pub(super) mod graphics;
pub(super) mod init;
pub(super) mod resize;
pub(super) mod scroll;
pub(super) mod scrollback;

// ── Shared test helpers ───────────────────────────────────────────────────────

/// Construct a standard 24×80 [`Screen`] for screen unit tests.
#[allow(dead_code, reason = "shared helper; not every test submodule calls it")]
pub(super) fn make_screen() -> crate::grid::screen::Screen {
    crate::grid::screen::Screen::new(24, 80)
}

/// Assert that the cell at `(row, col)` in `screen` contains the character `expected`.
///
/// Usage:
/// ```ignore
/// assert_cell_char!(screen, row, col, 'A');
/// ```
macro_rules! assert_cell_char {
    ($screen:expr, $row:expr, $col:expr, $expected:expr) => {
        assert_eq!(
            $screen.get_cell($row, $col).unwrap().char(),
            $expected,
            "expected cell ({}, {}) = {:?}",
            $row,
            $col,
            $expected
        )
    };
    ($screen:expr, $row:expr, $col:expr, $expected:expr, $msg:expr) => {
        assert_eq!(
            $screen.get_cell($row, $col).unwrap().char(),
            $expected,
            $msg
        )
    };
}

pub(super) use assert_cell_char;
