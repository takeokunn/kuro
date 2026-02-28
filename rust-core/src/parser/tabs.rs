//! Tab stop management

/// Tab stop manager using bitmap for O(1) tab stop lookups
///
/// Uses a Vec<bool> bitmap where index i represents whether there's a tab stop at column i.
/// This provides constant-time set/clear operations and linear scan for next_stop, which
/// is efficient for typical terminal widths (< 256 columns).
#[derive(Debug, Clone)]
pub struct TabStops {
    /// Bitmap of tab stops - true if tab at column i
    stops: Vec<bool>,
    /// Number of columns in the terminal
    cols: usize,
}

impl TabStops {
    /// Create a new tab stop manager with default stops every 8 columns
    pub fn new(cols: usize) -> Self {
        let mut stops = vec![false; cols];
        // Default tabs every 8 columns
        let mut col = 8;
        while col < cols {
            stops[col] = true;
            col += 8;
        }

        Self { stops, cols }
    }

    /// Set a tab stop at the specified column (0-indexed)
    pub fn set_stop(&mut self, col: usize) {
        if col < self.cols {
            self.stops[col] = true;
        }
    }

    /// Clear tab stop at the specified column (Ps=0)
    /// Clear all tab stops (Ps=3)
    pub fn clear_stop(&mut self, col: Option<usize>) {
        match col {
            Some(c) => {
                // Clear single tab stop
                if c < self.cols {
                    self.stops[c] = false;
                }
            }
            None => {
                // Clear all tab stops and reset to defaults
                self.stops.fill(false);
                let mut c = 8;
                while c < self.cols {
                    self.stops[c] = true;
                    c += 8;
                }
            }
        }
    }

    /// Find the next tab stop at or after the specified column
    ///
    /// This performs a linear scan from the specified column, which is O(cols) in worst case
    /// but typically O(cols/8) since tab stops are usually spaced every 8 columns.
    /// For typical terminals (< 256 columns), this is very fast and eliminates the
    /// O(n log n) sort operation from the previous HashSet implementation.
    pub fn next_stop(&self, from: usize) -> usize {
        // Find the first tab stop >= from
        for i in from..self.cols {
            if self.stops[i] {
                return i;
            }
        }

        // No tab stop found, stay at end of screen
        self.cols.saturating_sub(1)
    }

    /// Resize the tab stop manager
    pub fn resize(&mut self, new_cols: usize) {
        self.cols = new_cols;

        // Expand or shrink the bitmap
        if new_cols > self.stops.len() {
            self.stops.resize(new_cols, false);
        } else {
            self.stops.truncate(new_cols);
        }

        // Add default stops if needed (every 8 columns)
        let mut col = 8;
        while col < new_cols {
            if !self.stops[col] {
                self.stops[col] = true;
            }
            col += 8;
        }
    }

    /// Get a copy of all tab stops as a sorted vector
    pub fn get_stops(&self) -> Vec<usize> {
        self.stops
            .iter()
            .enumerate()
            .filter(|(_, &is_set)| is_set)
            .map(|(i, _)| i)
            .collect()
    }

    /// Restore tab stops from a saved state
    ///
    /// Note: The saved state is now a Vec<bool> bitmap for consistency with the new implementation.
    /// This maintains the same interface but changes the internal representation.
    pub fn restore(&mut self, stops: Vec<bool>) {
        // Use the saved stops, truncated/padded to current width
        self.stops = if stops.len() >= self.cols {
            stops[..self.cols].to_vec()
        } else {
            let mut result = stops;
            result.resize(self.cols, false);
            result
        };
    }

    /// Get a copy of tab stops for saving
    ///
    /// Returns the full bitmap state for restoration.
    pub fn save(&self) -> Vec<bool> {
        self.stops.clone()
    }
}

/// Handle horizontal tab (HT - 0x09)
///
/// Move cursor to the next tab stop.
pub fn handle_ht(screen: &mut crate::grid::Screen, tabs: &TabStops) {
    let current_col = screen.cursor().col;
    let next_stop = tabs.next_stop(current_col + 1); // +1 to move forward
    screen.cursor_mut().col = next_stop.min(screen.cols() as usize - 1);
}

/// Handle horizontal tab set (HTS - ESC H)
///
/// Set a tab stop at the current cursor column.
pub fn handle_hts(screen: &crate::grid::Screen, tabs: &mut TabStops) {
    tabs.set_stop(screen.cursor().col);
}

/// Handle tab clear (TBC - CSI g)
///
/// Clear tab stop(s).
/// - Ps = 0 (default): Clear tab stop at current cursor column
/// - Ps = 3: Clear all tab stops
pub fn handle_tbc(screen: &crate::grid::Screen, tabs: &mut TabStops, params: &vte::Params) {
    let mode = params
        .iter()
        .next()
        .and_then(|p| p.iter().next())
        .copied()
        .unwrap_or(0);

    match mode {
        0 => {
            // Clear tab stop at current cursor column
            tabs.clear_stop(Some(screen.cursor().col));
        }
        3 => {
            // Clear all tab stops (reset to defaults)
            tabs.clear_stop(None);
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tabs_default_stops() {
        let tabs = TabStops::new(80);
        let stops = tabs.get_stops();

        // Should have default tabs every 8 columns
        assert!(stops.contains(&8));
        assert!(stops.contains(&16));
        assert!(stops.contains(&24));
        assert!(stops.contains(&72));
    }

    #[test]
    fn test_set_stop() {
        let mut tabs = TabStops::new(80);

        // Set custom tab at column 5
        tabs.set_stop(5);
        let stops = tabs.get_stops();

        assert!(stops.contains(&5));
    }

    #[test]
    fn test_clear_stop() {
        let mut tabs = TabStops::new(80);

        // Remove default tab at column 8
        tabs.clear_stop(Some(8));
        let stops = tabs.get_stops();

        assert!(!stops.contains(&8));
        assert!(stops.contains(&16)); // Other defaults should remain
    }

    #[test]
    fn test_clear_all_stops() {
        let mut tabs = TabStops::new(80);

        // Add some custom stops
        tabs.set_stop(5);
        tabs.set_stop(10);

        // Clear all stops
        tabs.clear_stop(None);
        let stops = tabs.get_stops();

        // Should be back to defaults
        assert!(stops.contains(&8));
        assert!(stops.contains(&16));
        assert!(!stops.contains(&5));
        assert!(!stops.contains(&10));
    }

    #[test]
    fn test_next_stop() {
        let tabs = TabStops::new(80);

        // From column 0, next stop should be 8
        assert_eq!(tabs.next_stop(0), 8);

        // From column 5, next stop should be 8
        assert_eq!(tabs.next_stop(5), 8);

        // From column 8, next stop should be 8 (already at stop)
        assert_eq!(tabs.next_stop(8), 8);

        // From column 9, next stop should be 16
        assert_eq!(tabs.next_stop(9), 16);

        // From beyond last stop, should return end of screen
        let next = tabs.next_stop(75);
        assert!(next <= 79);
    }

    #[test]
    fn test_handle_ht() {
        let mut screen = crate::grid::Screen::new(24, 80);
        let tabs = TabStops::new(80);

        // Start at column 0
        assert_eq!(screen.cursor.col, 0);

        // Horizontal tab
        handle_ht(&mut screen, &tabs);

        // Should move to first tab stop (column 8)
        assert_eq!(screen.cursor.col, 8);
    }

    #[test]
    fn test_handle_ht_multiple() {
        let mut screen = crate::grid::Screen::new(24, 80);
        let tabs = TabStops::new(80);

        // Start at column 10
        screen.cursor.col = 10;

        handle_ht(&mut screen, &tabs);

        // Should move to next tab stop (column 16)
        assert_eq!(screen.cursor.col, 16);
    }

    #[test]
    fn test_handle_hts() {
        let mut screen = crate::grid::Screen::new(24, 80);
        let mut tabs = TabStops::new(80);

        // Move cursor to column 5
        screen.cursor.col = 5;

        // Set tab stop at cursor
        handle_hts(&screen, &mut tabs);

        let stops = tabs.get_stops();
        assert!(stops.contains(&5));
    }

    #[test]
    fn test_handle_tbc_clear_current() {
        let mut screen = crate::grid::Screen::new(24, 80);
        let mut tabs = TabStops::new(80);

        // Move cursor to column 8 (default tab stop)
        screen.cursor.col = 8;

        // Clear tab stop at cursor
        let params = vte::Params::default();
        handle_tbc(&screen, &mut tabs, &params);

        let stops = tabs.get_stops();
        assert!(!stops.contains(&8));
    }

    #[test]
    fn test_handle_tbc_clear_all() {
        // Use TerminalCore.advance to send CSI 3 g (TBC - clear all tab stops)
        let mut term = crate::TerminalCore::new(24, 80);

        // Add custom stops
        term.tab_stops.set_stop(5);
        term.tab_stops.set_stop(10);

        // Clear all tab stops via escape sequence (CSI 3 g)
        term.advance(b"\x1b[3g");

        // Should be back to defaults
        let stops = term.tab_stops.get_stops();
        assert!(stops.contains(&8));
        assert!(stops.contains(&16));
        assert!(!stops.contains(&5));
        assert!(!stops.contains(&10));
    }

    #[test]
    fn test_resize_tabs() {
        let mut tabs = TabStops::new(80);

        // Resize to 40 columns
        tabs.resize(40);

        // Stops beyond 40 should be removed
        let stops = tabs.get_stops();
        assert!(stops.contains(&8));
        assert!(stops.contains(&16));
        assert!(stops.contains(&24));
        assert!(stops.contains(&32));
        assert!(!stops.contains(&40));
        assert!(!stops.contains(&72));
    }

    #[test]
    fn test_save_restore_tabs() {
        let mut tabs = TabStops::new(80);

        // Add custom stops
        tabs.set_stop(5);
        tabs.set_stop(10);
        tabs.clear_stop(Some(8)); // Remove default tab at 8

        // Save
        let saved = tabs.save();

        // Modify
        tabs.clear_stop(None); // Reset to defaults

        // Verify changed
        let stops = tabs.get_stops();
        assert!(stops.contains(&8)); // Back to default

        // Restore
        tabs.restore(saved);

        // Verify restored
        let stops = tabs.get_stops();
        assert!(stops.contains(&5));
        assert!(stops.contains(&10));
        assert!(!stops.contains(&8));
    }

    #[test]
    fn test_tabs_clamps_to_width() {
        let mut tabs = TabStops::new(40);

        // Try to set stop beyond width
        tabs.set_stop(100);
        let stops = tabs.get_stops();

        assert!(!stops.contains(&100));
    }
}
