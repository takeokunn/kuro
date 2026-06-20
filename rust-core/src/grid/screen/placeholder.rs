//! Walk the active grid for Kitty Unicode placeholder (`U+10EEEE`) cells and
//! group contiguous same-image / same-placement runs into renderable rectangles.
//!
//! The result feeds `kuro_core_poll_placeholder_placements`, which exports each
//! [`PlaceholderRegion`] to Emacs so it can fetch the referenced image once and
//! slice it into per-cell tiles (fit-to-rectangle). Orphan placeholders — those
//! referencing an image id no longer in the graphics store — are excluded so
//! they never produce a tile that would render nothing.

use super::Screen;
use crate::grid::placeholder::{decode_placeholder, PlaceholderRegion};

/// A single decoded placeholder cell as seen during the grid walk.
#[derive(Clone, Copy)]
struct PlaceholderCell {
    image_id: u32,
    placement_id: u32,
    img_row: u32,
    img_col: u32,
}

/// A horizontal run of placeholder cells sharing image id + placement id on one
/// screen row, before vertical merging into a full rectangle.
struct HorizontalRun {
    image_id: u32,
    placement_id: u32,
    screen_row: usize,
    screen_col: usize,
    cell_cols: usize,
    /// Image-grid (row, col) of the run's left-most tile.
    img_row: u32,
    img_col: u32,
    /// Distinct image-grid columns the run spans (max img_col seen − min + 1).
    img_cols: u32,
}

impl Screen {
    /// Walk the active screen for `U+10EEEE` placeholder cells and return one
    /// [`PlaceholderRegion`] per contiguous same-image / same-placement
    /// rectangle.
    ///
    /// Cheap when there are no placeholders: a single linear scan over the grid
    /// that allocates nothing until the first placeholder is found.
    #[must_use]
    pub fn collect_placeholder_regions(&self) -> Vec<PlaceholderRegion> {
        let Some(screen) = self.active_screen() else {
            return Vec::new();
        };
        let rows = screen.rows() as usize;
        let cols = screen.cols() as usize;

        let mut runs: Vec<HorizontalRun> = Vec::new();
        for row in 0..rows {
            let Some(line) = screen.lines.get(row) else {
                continue;
            };
            screen.collect_row_runs(line, row, cols, &mut runs);
        }

        Self::merge_runs_into_regions(runs)
    }

    /// Decode one screen row into horizontal placeholder runs, appending them to
    /// `runs`. A run breaks when the image id, placement id, or contiguity (a
    /// non-placeholder / orphan cell) changes.
    fn collect_row_runs(
        &self,
        line: &crate::grid::line::Line,
        row: usize,
        cols: usize,
        runs: &mut Vec<HorizontalRun>,
    ) {
        let mut current: Option<HorizontalRun> = None;
        for col in 0..cols {
            let decoded = line
                .cells
                .get(col)
                .and_then(|cell| self.decode_renderable_placeholder(cell));

            match decoded {
                Some(pc) => match current.as_mut() {
                    // Extend the active run when it stays on the same image/placement.
                    Some(run)
                        if run.image_id == pc.image_id
                            && run.placement_id == pc.placement_id =>
                    {
                        run.cell_cols += 1;
                        // Span from the run's origin column to this tile. Guard
                        // against a tile whose img_col is *smaller* than the
                        // origin (non-monotonic encoding): a naive
                        // `img_col + 1 - base` would underflow (u32 wrap →
                        // garbage span). Saturate so the span never wraps; such
                        // tiles simply don't extend the run rightward.
                        let span = (pc.img_col + 1).saturating_sub(run.img_col_base());
                        run.img_cols = run.img_cols.max(span);
                    }
                    // A different image/placement starts a fresh run.
                    _ => {
                        if let Some(run) = current.take() {
                            runs.push(run);
                        }
                        current = Some(HorizontalRun {
                            image_id: pc.image_id,
                            placement_id: pc.placement_id,
                            screen_row: row,
                            screen_col: col,
                            cell_cols: 1,
                            img_row: pc.img_row,
                            img_col: pc.img_col,
                            img_cols: 1,
                        });
                    }
                },
                None => {
                    if let Some(run) = current.take() {
                        runs.push(run);
                    }
                }
            }
        }
        if let Some(run) = current.take() {
            runs.push(run);
        }
    }

    /// Decode a single cell as a *renderable* placeholder: returns `None` unless
    /// the cell is a `U+10EEEE` placeholder whose foreground encodes an image id
    /// that is currently stored (orphans are excluded). Placement id is
    /// normalised to `0` when none is encoded.
    #[inline]
    fn decode_renderable_placeholder(&self, cell: &crate::types::Cell) -> Option<PlaceholderCell> {
        let info =
            decode_placeholder(cell.grapheme(), cell.attrs.foreground, cell.attrs.underline_color)?;
        if !self.active_graphics().contains_image(info.image_id) {
            return None;
        }
        Some(PlaceholderCell {
            image_id: info.image_id,
            placement_id: info.placement_id.unwrap_or(0),
            img_row: info.img_row,
            img_col: info.img_col,
        })
    }

    /// Greedily merge vertically-adjacent horizontal runs (same image,
    /// placement, screen column span, and cell width) into rectangles, then turn
    /// every (merged or standalone) run into a [`PlaceholderRegion`].
    fn merge_runs_into_regions(runs: Vec<HorizontalRun>) -> Vec<PlaceholderRegion> {
        let mut regions: Vec<PlaceholderRegion> = Vec::new();
        let mut consumed = vec![false; runs.len()];

        for i in 0..runs.len() {
            if consumed[i] {
                continue;
            }
            // Start a rectangle from run i and extend downward while the run
            // directly below matches column span + image + placement.
            let mut cell_rows = 1usize;
            let mut max_img_cols = runs[i].img_cols;
            let mut max_img_row = runs[i].img_row;
            let mut next_row = runs[i].screen_row + 1;
            loop {
                let Some(j) = runs.iter().enumerate().position(|(k, r)| {
                    !consumed[k]
                        && k != i
                        && r.screen_row == next_row
                        && r.screen_col == runs[i].screen_col
                        && r.cell_cols == runs[i].cell_cols
                        && r.image_id == runs[i].image_id
                        && r.placement_id == runs[i].placement_id
                }) else {
                    break;
                };
                consumed[j] = true;
                cell_rows += 1;
                max_img_cols = max_img_cols.max(runs[j].img_cols);
                max_img_row = max_img_row.max(runs[j].img_row);
                next_row += 1;
            }

            let run = &runs[i];
            let img_rows = max_img_row + 1 - run.img_row;
            regions.push(PlaceholderRegion {
                image_id: run.image_id,
                placement_id: run.placement_id,
                screen_row: run.screen_row,
                screen_col: run.screen_col,
                cell_cols: run.cell_cols,
                cell_rows,
                img_row: run.img_row,
                img_col: run.img_col,
                img_rows,
                img_cols: max_img_cols,
            });
            consumed[i] = true;
        }

        regions
    }
}

impl HorizontalRun {
    /// The image-grid column of the run's left edge (its origin), used to compute
    /// how many distinct image columns the run currently spans.
    #[inline]
    const fn img_col_base(&self) -> u32 {
        self.img_col
    }
}

#[cfg(test)]
#[path = "placeholder/tests.rs"]
mod tests;
