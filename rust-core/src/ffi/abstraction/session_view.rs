// Rendering, cursor, scrollback, and metadata accessors for TerminalSession.

use super::TerminalSession;
use crate::Result;

fn encode_dirty_row(
    screen: &crate::grid::screen::Screen,
    row: usize,
) -> Option<(usize, String)> {
    screen.get_line(row).map(|line| {
        let text: String = line
            .cells
            .iter()
            .map(|cell| cell.grapheme.as_str())
            .collect();
        (row, text)
    })
}

fn collect_encoded_dirty_rows<I>(
    screen: &crate::grid::screen::Screen,
    rows: I,
) -> Vec<(usize, String)>
where
    I: IntoIterator<Item = usize>,
{
    let mut result = Vec::new();
    for row in rows {
        if let Some(encoded) = encode_dirty_row(screen, row) {
            result.push(encoded);
        }
    }
    result
}

impl TerminalSession {
    /// Return all rows that need to be re-rendered, encoded as `(row, text)`.
    ///
    /// Full-dirty mode walks every visible row; partial-dirty mode only walks
    /// the rows reported by the dirty tracker.
    #[must_use]
    pub fn get_dirty_lines(&mut self) -> Vec<(usize, String)> {
        let rows = self.core.screen.rows() as usize;
        if self.core.screen.is_full_dirty() {
            self.core.screen.clear_dirty();
            collect_encoded_dirty_rows(&self.core.screen, 0..rows)
        } else {
            let dirty_rows = self.core.screen.take_dirty_lines();
            collect_encoded_dirty_rows(&self.core.screen, dirty_rows)
        }
    }

    /// Encode a terminal color as the FFI color value used by the frontend.
    #[inline]
    #[must_use]
    pub fn encode_color(color: &crate::types::Color) -> u32 {
        crate::ffi::codec::encode_color(color)
    }

    /// Encode a cell attribute record to the compact FFI representation.
    #[inline]
    #[must_use]
    pub fn encode_attrs(attrs: &crate::types::cell::SgrAttributes) -> u64 {
        crate::ffi::codec::encode_attrs(attrs)
    }

    /// Encode a line of cells into text and face ranges.
    #[must_use]
    pub fn encode_line_faces(
        row: usize,
        cells: &[crate::types::cell::Cell],
    ) -> crate::ffi::codec::EncodedLine {
        let (text, face_ranges, col_to_buf) = crate::ffi::codec::encode_line(cells);
        (row, text, face_ranges, col_to_buf)
    }

    /// Resize the terminal core and PTY, if any.
    pub fn resize(&mut self, rows: u16, cols: u16) -> Result<()> {
        self.core.resize(rows, cols);
        self.row_hashes.resize(rows as usize, None);
        for slot in &mut self.row_hashes {
            *slot = None;
        }

        #[cfg(unix)]
        if let Some(ref mut pty) = self.pty {
            pty.set_winsize(rows, cols)?;
        }

        Ok(())
    }

    /// Return the current cursor position as `(row, col)`.
    #[must_use]
    pub fn get_cursor(&self) -> (usize, usize) {
        let c = self.core.screen.cursor();
        (c.row, c.col)
    }

    /// Return the current cursor visibility state.
    #[must_use]
    pub const fn get_cursor_visible(&self) -> bool {
        self.core.dec_modes.cursor_visible
    }

    /// Return the current scrollback lines.
    #[must_use]
    pub fn get_scrollback(&self, max_lines: usize) -> Vec<String> {
        let lines = self.core.screen.get_scrollback_lines(max_lines);
        lines.iter().map(std::string::ToString::to_string).collect()
    }

    /// Clear the scrollback buffer.
    pub fn clear_scrollback(&mut self) {
        self.core.screen.clear_scrollback();
    }

    /// Set the maximum number of scrollback lines retained by the screen.
    pub fn set_scrollback_max_lines(&mut self, lines: usize) {
        self.core.screen.set_scrollback_max_lines(lines);
    }

    /// Set the terminal color scheme used by fallback rendering.
    pub fn set_color_scheme(&mut self, is_dark: bool) -> bool {
        crate::parser::dec_private::apply_color_scheme(&mut self.core, is_dark)
    }

    /// Return the currently displayed kitty image as a base64 PNG payload, if any.
    #[must_use]
    pub fn get_image_png_base64(&self, image_id: u32) -> String {
        self.core.screen.get_image_png_base64(image_id)
    }
}
