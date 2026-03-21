//! Tab stop management

/// Tab stop manager using bitmap for O(1) tab stop lookups
///
/// Uses a `Vec<bool>` bitmap where index i represents whether there's a tab stop at column i.
/// This provides constant-time set/clear operations and linear scan for `next_stop`, which
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
    #[must_use]
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
        if let Some(c) = col {
            // Clear single tab stop
            if c < self.cols {
                self.stops[c] = false;
            }
        } else {
            // Clear all tab stops and reset to defaults
            self.stops.fill(false);
            let mut c = 8;
            while c < self.cols {
                self.stops[c] = true;
                c += 8;
            }
        }
    }

    /// Find the next tab stop at or after the specified column
    ///
    /// This performs a linear scan from the specified column, which is O(cols) in worst case
    /// but typically O(cols/8) since tab stops are usually spaced every 8 columns.
    /// For typical terminals (< 256 columns), this is very fast and eliminates the
    /// O(n log n) sort operation from the previous `HashSet` implementation.
    #[must_use]
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
    #[must_use]
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
    /// Note: The saved state is now a `Vec<bool>` bitmap for consistency with the new implementation.
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
    #[must_use]
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
#[path = "tests/tabs.rs"]
mod tests;
