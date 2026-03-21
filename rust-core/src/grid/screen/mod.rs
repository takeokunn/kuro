//! Virtual screen buffer with dirty tracking

use super::super::types::{Cell, CellWidth, Color, Cursor, SgrAttributes};
use super::dirty_set::{BitVecDirtySet, DirtySet};
use super::line::Line;
use std::collections::VecDeque;
use unicode_width::UnicodeWidthChar;

// Re-export image types so existing `use crate::grid::screen::*` paths keep working
pub use crate::grid::image::{GraphicsStore, ImageData, ImageNotification, ImagePlacement};

mod alternate;
mod cursor;
mod dirty;
mod edit;
mod graphics;
mod resize;
pub mod scroll;
mod scrollback;

/// Default maximum scrollback buffer size in lines.
///
/// At ~80 columns per line the Rust `Cell` representation is approximately
/// 64 bytes/cell, giving a rough budget of 10,000 × 80 × 64 ≈ 51 MiB.
/// This value is overridden at runtime by the Emacs-side `kuro-scrollback-size`
/// custom variable via `kuro-core-set-scrollback-max-lines`.
pub(crate) const DEFAULT_SCROLLBACK_MAX: usize = 10_000;

#[cfg(test)]
#[path = "../tests/screen.rs"]
mod tests;

/// Scroll region for DECSTBM
#[derive(Debug, Clone, Copy)]
pub struct ScrollRegion {
    /// Top margin (inclusive)
    pub(crate) top: usize,
    /// Bottom margin (exclusive)
    pub(crate) bottom: usize,
}

impl ScrollRegion {
    /// Create a new scroll region
    #[inline]
    #[must_use]
    pub const fn new(top: usize, bottom: usize) -> Self {
        Self { top, bottom }
    }

    /// Create default scroll region (entire screen)
    #[inline]
    #[must_use]
    pub const fn full_screen(rows: usize) -> Self {
        Self {
            top: 0,
            bottom: rows,
        }
    }
}

/// Virtual screen representing the terminal display
#[derive(Debug)]
#[expect(
    clippy::struct_field_names,
    reason = "alternate_screen is the established name for DEC 1049 alternate buffer; renaming would reduce clarity"
)]
pub struct Screen {
    /// Lines in the screen (`VecDeque` enables O(1) full-screen scroll via rotate)
    pub(super) lines: VecDeque<Line>,
    /// Cursor state
    pub(crate) cursor: Cursor,
    /// Set of dirty line indices (bit-vector backed for O(1) insert)
    pub(super) dirty_set: BitVecDirtySet,
    /// When true, all lines are dirty (overrides `dirty_set` for efficiency)
    pub(super) full_dirty: bool,
    /// Scroll region
    pub(super) scroll_region: ScrollRegion,
    /// Number of rows
    pub(super) rows: u16,
    /// Number of columns
    pub(super) cols: u16,
    /// Alternate screen buffer (for DEC mode 1049)
    pub(super) alternate_screen: Option<Box<Self>>,
    /// Whether alternate screen is currently active
    pub(super) is_alternate_active: bool,
    /// Saved primary cursor position when switching to alternate
    pub(super) saved_primary_cursor: Option<Cursor>,
    /// Saved scroll region when switching to alternate
    pub(super) saved_scroll_region: Option<ScrollRegion>,
    /// Scrollback buffer for preserving scrolled content
    pub(crate) scrollback_buffer: VecDeque<Line>,
    /// Number of lines currently in scrollback buffer
    pub(crate) scrollback_line_count: usize,
    /// Maximum scrollback buffer size (configured from Emacs)
    pub(crate) scrollback_max_lines: usize,
    /// Current viewport scroll offset (0 = live view, N = scrolled back N lines)
    pub(crate) scroll_offset: usize,
    /// Whether the viewport scroll position has changed and needs re-render
    pub(super) scroll_dirty: bool,
    /// Image placement store for Kitty Graphics Protocol
    pub(crate) graphics: GraphicsStore,
    /// Accumulated full-screen scroll-up count since last `consume_scroll_events` call.
    /// Used by the Emacs render cycle to perform buffer-level delete+insert instead
    /// of rewriting every dirty row, eliminating O(N) line renders per scroll step.
    pub(crate) pending_scroll_up: u32,
    /// Accumulated full-screen scroll-down count since last `consume_scroll_events` call.
    pub(crate) pending_scroll_down: u32,
}

impl Screen {
    /// Create a new screen with the specified dimensions
    #[must_use]
    pub fn new(rows: u16, cols: u16) -> Self {
        let lines: VecDeque<Line> = (0..rows).map(|_| Line::new(cols as usize)).collect();

        Self {
            lines,
            cursor: Cursor::new(0, 0),
            dirty_set: BitVecDirtySet::new(rows as usize),
            full_dirty: false,
            scroll_region: ScrollRegion::full_screen(rows as usize),
            rows,
            cols,
            alternate_screen: None,
            is_alternate_active: false,
            saved_primary_cursor: None,
            saved_scroll_region: None,
            scrollback_buffer: VecDeque::new(),
            scrollback_line_count: 0,
            scrollback_max_lines: DEFAULT_SCROLLBACK_MAX,
            scroll_offset: 0,
            scroll_dirty: false,
            graphics: GraphicsStore::new(),
            pending_scroll_up: 0,
            pending_scroll_down: 0,
        }
    }

    /// Get number of rows
    #[inline]
    #[must_use]
    pub const fn rows(&self) -> u16 {
        self.rows
    }

    /// Get number of columns
    #[inline]
    #[must_use]
    pub const fn cols(&self) -> u16 {
        self.cols
    }

    /// Return a reference to the line buffer of the currently active screen.
    ///
    /// When the alternate screen is active the alternate buffer's `lines`
    /// `VecDeque` is returned; otherwise the primary buffer's `lines` is
    /// returned.  Returns `None` only when `is_alternate_active` is true but
    /// `alternate_screen` is `None` (invariant violation).
    #[inline]
    fn active_lines(&self) -> Option<&VecDeque<Line>> {
        if self.is_alternate_active {
            debug_assert!(
                self.alternate_screen.is_some(),
                "Screen invariant violated: is_alternate_active=true but alternate_screen=None"
            );
            self.alternate_screen.as_ref().map(|s| {
                debug_assert!(
                    s.lines.len() == s.rows as usize,
                    "alt_lines length {} != rows {}",
                    s.lines.len(),
                    s.rows
                );
                &s.lines
            })
        } else {
            Some(&self.lines)
        }
    }

    /// Return a mutable reference to the line buffer of the currently active screen.
    ///
    /// When the alternate screen is active the alternate buffer's `lines`
    /// `VecDeque` is returned; otherwise the primary buffer's `lines` is
    /// returned.  Returns `None` only when `is_alternate_active` is true but
    /// `alternate_screen` is `None` (invariant violation).
    ///
    /// See [`Self::active_lines`] for full invariant documentation.
    #[inline]
    fn active_lines_mut(&mut self) -> Option<&mut VecDeque<Line>> {
        if self.is_alternate_active {
            debug_assert!(
                self.alternate_screen.is_some(),
                "Screen invariant violated: is_alternate_active=true but alternate_screen=None"
            );
            self.alternate_screen.as_mut().map(|s| {
                debug_assert!(
                    s.lines.len() == s.rows as usize,
                    "alt_lines length {} != rows {}",
                    s.lines.len(),
                    s.rows
                );
                &mut s.lines
            })
        } else {
            Some(&mut self.lines)
        }
    }

    /// Get cell at position
    #[inline]
    #[must_use]
    pub fn get_cell(&self, row: usize, col: usize) -> Option<&Cell> {
        self.active_lines()?.get(row)?.get_cell(col)
    }

    /// Get mutable cell at position
    #[inline]
    pub fn get_cell_mut(&mut self, row: usize, col: usize) -> Option<&mut Cell> {
        self.active_lines_mut()?.get_mut(row)?.cells.get_mut(col)
    }

    /// Get line data at row
    #[inline]
    #[must_use]
    pub fn get_line(&self, row: usize) -> Option<&Line> {
        self.active_lines()?.get(row)
    }

    /// Get mutable line data at row
    #[inline]
    pub fn get_line_mut(&mut self, row: usize) -> Option<&mut Line> {
        self.active_lines_mut()?.get_mut(row)
    }

    /// Get mutable reference to the currently active screen
    #[inline]
    pub(super) fn active_screen_mut(&mut self) -> Option<&mut Self> {
        if self.is_alternate_active {
            debug_assert!(
                self.alternate_screen.is_some(),
                "Screen invariant violated: is_alternate_active=true but alternate_screen=None"
            );
            self.alternate_screen
                .as_mut()
                .map(std::convert::AsMut::as_mut)
        } else {
            Some(self)
        }
    }

    /// Get reference to the currently active screen
    #[inline]
    pub(super) fn active_screen(&self) -> Option<&Self> {
        if self.is_alternate_active {
            debug_assert!(
                self.alternate_screen.is_some(),
                "Screen invariant violated: is_alternate_active=true but alternate_screen=None"
            );
            self.alternate_screen
                .as_ref()
                .map(std::convert::AsRef::as_ref)
        } else {
            Some(self)
        }
    }
}
