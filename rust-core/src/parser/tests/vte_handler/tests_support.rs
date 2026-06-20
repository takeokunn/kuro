/// Create a standard 24×80 `TerminalCore` pre-fed with `$bytes`.
///
/// ```
/// let term = term_with!(b"Hello");
/// ```
macro_rules! term_with {
    ($bytes:expr) => {{
        let mut _t = crate::TerminalCore::new(24, 80);
        _t.advance($bytes);
        _t
    }};
}

/// Assert a single cell's character value.
///
/// ```
/// assert_cell_char!(term, row 0, col 2, 'l');
/// ```
macro_rules! assert_cell_char {
    ($term:expr, row $r:expr, col $c:expr, $ch:expr) => {{
        assert_eq!(
            $term.screen.get_cell($r, $c).unwrap().char(),
            $ch,
            "cell ({}, {}) expected {:?}",
            $r,
            $c,
            $ch
        );
    }};
}

/// Assert the cursor is at an exact (row, col) position.
///
/// ```
/// assert_cursor!(term, row 4, col 0);
/// ```
macro_rules! assert_cursor {
    ($term:expr, row $r:expr, col $c:expr) => {{
        assert_eq!(
            $term.screen.cursor().row,
            $r,
            "cursor row: expected {}, got {}",
            $r,
            $term.screen.cursor().row
        );
        assert_eq!(
            $term.screen.cursor().col,
            $c,
            "cursor col: expected {}, got {}",
            $c,
            $term.screen.cursor().col
        );
    }};
}

pub(crate) fn first_pending_response_bytes(core: &crate::TerminalCore) -> &[u8] {
    &core.meta.pending_responses[0]
}

pub(crate) fn assert_no_pending_responses(core: &crate::TerminalCore) {
    assert!(
        core.meta.pending_responses.is_empty(),
        "expected no queued responses, got {:?}",
        core.meta.pending_responses
    );
}

pub(crate) fn assert_pending_response_count(core: &crate::TerminalCore, count: usize) {
    assert_eq!(
        core.meta.pending_responses.len(),
        count,
        "expected {} queued responses, got {:?}",
        count,
        core.meta.pending_responses
    );
}

pub(crate) fn assert_single_pending_response_bytes(core: &crate::TerminalCore, expected: &[u8]) {
    assert_eq!(
        core.meta.pending_responses,
        vec![expected.to_vec()],
        "expected a single queued response {:?}, got {:?}",
        expected,
        core.meta.pending_responses
    );
}

/// Assert `meta.pending_responses` is non-empty and that the first entry
/// starts with `$prefix` (as a byte slice).
///
/// ```
/// assert_response_starts!(term, b"\x1b[?");
/// ```
macro_rules! assert_response_starts {
    ($term:expr, $prefix:expr) => {{
        crate::parser::vte_handler::tests::assert_pending_response_count(&$term, 1);
        assert!(
            crate::parser::vte_handler::tests::first_pending_response_bytes(&$term)
                .starts_with($prefix),
            "response should start with {:?}, got {:?}",
            $prefix,
            crate::parser::vte_handler::tests::first_pending_response_bytes(&$term)
        );
    }};
}

/// Assert that an SGR sequence sets a specific flag bit in `current_attrs`.
///
/// ```
/// assert_sgr_flag!(b"\x1b[3m", SgrFlags::ITALIC, "SGR 3 must set ITALIC");
/// ```
macro_rules! assert_sgr_flag {
    ($seq:expr, $flag:expr, $msg:expr) => {{
        let _t = term_with!($seq);
        assert!(_t.current_attrs.flags.contains($flag), "{}", $msg);
    }};
}

/// Assert that a C0 control byte advances the cursor row by exactly `$delta` rows,
/// leaving the cursor within valid bounds.
///
/// Used for LF/VT/FF (0x0A–0x0C) which all act as line feeds.
///
/// ```
/// assert_c0_linefeed!(0x0A, 1, "LF");
/// ```
macro_rules! assert_c0_linefeed {
    ($byte:expr, $delta:expr, $label:expr) => {{
        let mut _t = crate::TerminalCore::new(24, 80);
        let _row_before = _t.screen.cursor.row;
        _t.advance(&[$byte]);
        assert_eq!(
            _t.screen.cursor.row,
            _row_before + $delta,
            "{} (0x{:02x}) must advance cursor row by {}",
            $label,
            $byte,
            $delta
        );
    }};
}

/// Generate a test asserting that `$seq` does NOT produce any pending response.
///
/// ```
/// assert_no_response!(test_so_no_response, b"\x0e");
/// ```
macro_rules! assert_no_response {
    ($name:ident, $seq:expr) => {
        #[test]
        fn $name() {
            let _t = term_with!($seq);
            crate::parser::vte_handler::tests::assert_no_pending_responses(&_t);
        }
    };
}
