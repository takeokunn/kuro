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

/// Assert `meta.pending_responses` is non-empty and that the first entry
/// starts with `$prefix` (as a byte slice).
///
/// ```
/// assert_response_starts!(term, b"\x1b[?");
/// ```
macro_rules! assert_response_starts {
    ($term:expr, $prefix:expr) => {{
        assert!(
            !$term.meta.pending_responses.is_empty(),
            "expected at least one queued response, got none"
        );
        assert!(
            $term.meta.pending_responses[0].starts_with($prefix),
            "response should start with {:?}, got {:?}",
            $prefix,
            &$term.meta.pending_responses[0]
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
            assert!(
                _t.meta.pending_responses.is_empty(),
                "sequence {:?} must not queue any response",
                $seq
            );
        }
    };
}
