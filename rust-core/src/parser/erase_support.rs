use crate::parser::sgr::{apply_sgr_attrs, collect_param_groups};
use crate::types::cell::SgrAttributes;
use crate::types::Cell;
use crate::TerminalCore;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Rect {
    top: usize,
    left: usize,
    bottom: usize,
    right: usize,
}

impl Rect {
    fn from_params(params: &vte::Params, rows: u16, cols: u16) -> Self {
        let mut iter = params.iter().filter_map(|p| p.first().copied());
        Self::from_iter(&mut iter, rows, cols)
    }

    fn from_iter(iter: &mut impl Iterator<Item = u16>, rows: u16, cols: u16) -> Self {
        let top = usize::from(iter.next().unwrap_or(1).max(1).saturating_sub(1));
        let left = usize::from(iter.next().unwrap_or(1).max(1).saturating_sub(1));
        let bottom = usize::from(iter.next().unwrap_or(rows).min(rows));
        let right = usize::from(iter.next().unwrap_or(cols).min(cols));
        Self {
            top,
            left,
            bottom,
            right,
        }
    }

    fn is_empty(self) -> bool {
        self.top >= self.bottom || self.left >= self.right
    }
}

fn deccara_rect_from_groups(groups: &[&[u16]], rows: u16, cols: u16) -> Rect {
    Rect {
        top: usize::from(
            groups
                .first()
                .and_then(|g| g.first())
                .copied()
                .unwrap_or(1)
                .max(1)
                .saturating_sub(1),
        ),
        left: usize::from(
            groups
                .get(1)
                .and_then(|g| g.first())
                .copied()
                .unwrap_or(1)
                .max(1)
                .saturating_sub(1),
        ),
        bottom: usize::from(
            groups
                .get(2)
                .and_then(|g| g.first())
                .copied()
                .unwrap_or(rows)
                .min(rows),
        ),
        right: usize::from(
            groups
                .get(3)
                .and_then(|g| g.first())
                .copied()
                .unwrap_or(cols)
                .min(cols),
        ),
    }
}

fn blank_cell_with_bg(bg: crate::types::color::Color) -> Cell {
    let mut blank = Cell::default();
    blank.attrs.background = bg;
    blank
}

fn apply_rect_cells<F>(term: &mut TerminalCore, rect: Rect, mut apply: F, bump_version: bool)
where
    F: FnMut(&mut Cell),
{
    if rect.is_empty() {
        return;
    }

    let rows = usize::from(term.screen.rows());
    let cols = usize::from(term.screen.cols());
    let bottom = rect.bottom.min(rows);
    let right = rect.right.min(cols);
    if rect.top >= bottom || rect.left >= right {
        return;
    }

    for row in rect.top..bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            for col in rect.left..right.min(line.cells.len()) {
                apply(&mut line.cells[col]);
            }
            if bump_version {
                line.mark_dirty_and_bump();
            }
        }
        term.screen.mark_line_dirty(row);
    }
}

fn copy_rect_cells(term: &TerminalCore, rect: Rect) -> Vec<Vec<Cell>> {
    let rows = usize::from(term.screen.rows());
    let cols = usize::from(term.screen.cols());
    let bottom = rect.bottom.min(rows);
    let right = rect.right.min(cols);

    if rect.top >= bottom || rect.left >= right {
        return Vec::new();
    }

    let mut buf = Vec::with_capacity(bottom.saturating_sub(rect.top));
    for row in rect.top..bottom {
        let mut row_buf = Vec::with_capacity(right.saturating_sub(rect.left));
        for col in rect.left..right {
            row_buf.push(term.screen.get_cell(row, col).cloned().unwrap_or_default());
        }
        buf.push(row_buf);
    }

    buf
}

fn write_rect_cells(term: &mut TerminalCore, top: usize, left: usize, cells: &[Vec<Cell>]) {
    let rows = usize::from(term.screen.rows());
    let cols = usize::from(term.screen.cols());

    for (ri, row_buf) in cells.iter().enumerate() {
        let dst_row = top + ri;
        if dst_row >= rows {
            break;
        }

        for (ci, cell) in row_buf.iter().enumerate() {
            let dst_col = left + ci;
            if dst_col >= cols {
                break;
            }
            if let Some(dst_cell) = term.screen.get_cell_mut(dst_row, dst_col) {
                *dst_cell = cell.clone();
            }
        }
        term.screen.mark_line_dirty(dst_row);
    }
}

pub(super) fn handle_decera(term: &mut TerminalCore, params: &vte::Params) {
    let rect = Rect::from_params(params, term.screen.rows(), term.screen.cols());
    let bg = term.current_attrs.background;
    let blank = blank_cell_with_bg(bg);
    apply_rect_cells(term, rect, |cell| *cell = blank.clone(), false);
}

pub(super) fn handle_decfra(term: &mut TerminalCore, params: &vte::Params) {
    let mut iter = params.iter();
    let ch_code = iter.next().and_then(|p| p.first()).copied().unwrap_or(0x20);
    let fill_char = char::from_u32(u32::from(ch_code)).unwrap_or(' ');

    let rect = Rect::from_iter(
        &mut iter.filter_map(|p| p.first().copied()),
        term.screen.rows(),
        term.screen.cols(),
    );

    let attrs = term.current_attrs;
    let fill = Cell::with_attrs(fill_char, attrs);
    apply_rect_cells(term, rect, |cell| *cell = fill.clone(), false);
}

pub(super) fn handle_deccra(term: &mut TerminalCore, params: &vte::Params) {
    let rows = term.screen.rows();
    let cols = term.screen.cols();
    let mut iter = params.iter().filter_map(|p| p.first().copied());
    let src = Rect::from_iter(&mut iter, rows, cols);
    let _src_page = iter.next();
    let dst_top = usize::from(iter.next().unwrap_or(1).max(1).saturating_sub(1));
    let dst_left = usize::from(iter.next().unwrap_or(1).max(1).saturating_sub(1));

    let cells = copy_rect_cells(term, src);
    if cells.is_empty() {
        return;
    }

    write_rect_cells(term, dst_top, dst_left, &cells);
}

pub(super) fn handle_deccara(term: &mut TerminalCore, params: &vte::Params) {
    let rows = term.screen.rows();
    let cols = term.screen.cols();

    let (group_buf, n) = collect_param_groups(params);
    let groups = &group_buf[..n];

    let rect = deccara_rect_from_groups(groups, rows, cols);

    if rect.is_empty() {
        return;
    }

    let sgr_groups = if groups.len() > 4 {
        &groups[4..]
    } else {
        &[][..]
    };
    let mut attrs = SgrAttributes::default();
    apply_sgr_attrs(&mut attrs, sgr_groups);

    for row in rect.top..rect.bottom {
        if let Some(line) = term.screen.get_line_mut(row) {
            for col in rect.left..rect.right.min(line.cells.len()) {
                line.cells[col].attrs = attrs;
            }
            line.mark_dirty_and_bump();
        }
        term.screen.mark_line_dirty(row);
    }
}
