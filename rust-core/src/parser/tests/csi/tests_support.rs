// ── Test helpers ──────────────────────────────────────────────────────────────

/// Construct a fresh `TerminalCore` with the given dimensions.
macro_rules! term {
    ($rows:expr, $cols:expr) => {
        crate::TerminalCore::new($rows, $cols)
    };
}

/// Assert cursor row and column in one expression.
macro_rules! assert_cursor {
    ($term:expr, $row:expr, $col:expr) => {
        assert_eq!($term.screen.cursor.row, $row, "cursor.row mismatch");
        assert_eq!($term.screen.cursor.col, $col, "cursor.col mismatch");
    };
    ($term:expr, row = $row:expr) => {
        assert_eq!($term.screen.cursor.row, $row, "cursor.row mismatch");
    };
    ($term:expr, col = $col:expr) => {
        assert_eq!($term.screen.cursor.col, $col, "cursor.col mismatch");
    };
}

/// Collect pending response bytes as UTF-8 text for assertion helpers.
pub fn pending_response_texts(core: &crate::TerminalCore) -> Vec<&str> {
    core.meta
        .pending_responses
        .iter()
        .map(|response| std::str::from_utf8(response).expect("response must be valid UTF-8"))
        .collect()
}

/// Assert that no pending responses were queued.
pub fn assert_no_pending_responses(core: &crate::TerminalCore) {
    assert!(
        core.meta.pending_responses.is_empty(),
        "expected no pending responses"
    );
}

/// Assert the exact number of queued pending responses.
pub fn assert_pending_response_count(core: &crate::TerminalCore, count: usize) {
    assert_eq!(
        core.meta.pending_responses.len(),
        count,
        "unexpected pending response count"
    );
}

/// Assert that the single pending response equals the expected bytes.
pub fn assert_single_pending_response_bytes(core: &crate::TerminalCore, expected: &[u8]) {
    assert_pending_response_count(core, 1);
    assert_eq!(
        core.meta.pending_responses[0], expected,
        "single pending response mismatch"
    );
}

/// Assert that the single pending response matches the expected UTF-8 text.
pub fn assert_single_pending_response_text(core: &crate::TerminalCore, expected: &str) {
    assert_eq!(
        pending_response_texts(core).as_slice(),
        [expected],
        "single pending response text mismatch"
    );
}

/// Table-driven macro for tests that: (a) create a fresh 24×80 terminal,
/// (b) feed a single CSI byte sequence, and (c) assert the resulting cursor.
///
/// Pattern: `test_name : b"sequence" => (row, col)`
macro_rules! test_cursor_commands {
    ($( $name:ident : $input:expr => ($row:expr, $col:expr) ),+ $(,)?) => {
        $(
            #[test]
            fn $name() {
                let mut term = term!(24, 80);
                term.advance($input);
                assert_cursor!(term, $row, $col);
            }
        )+
    };
}

/// Table-driven macro for tests that: (a) create a fresh 24×80 terminal,
/// (b) move the cursor to a known starting position, (c) feed a single CSI
/// byte sequence, and (d) assert the resulting cursor.
///
/// Pattern: `test_name : start (row, col), b"sequence" => (row, col)`
macro_rules! test_cursor_sequence {
    ($( $name:ident : start ($sr:expr, $sc:expr), $input:expr => ($row:expr, $col:expr) ),+ $(,)?) => {
        $(
            #[test]
            fn $name() {
                let mut term = term!(24, 80);
                term.screen.move_cursor($sr, $sc);
                term.advance($input);
                assert_cursor!(term, $row, $col);
            }
        )+
    };
}

/// Table-driven macro for testing that CSI cursor-movement functions treat an
/// absent parameter identically to an explicit 1.
///
/// Pattern: `test_name : fn_under_test , start (row, col) => expected (row, col)`
macro_rules! test_cursor_default {
    (
        $(
            $name:ident : $fn:ident , ($sr:expr, $sc:expr) => ($er:expr, $ec:expr)
        ),+ $(,)?
    ) => {
        $(
            #[test]
            fn $name() {
                let mut term = term!(24, 80);
                term.screen.move_cursor($sr, $sc);
                let params = vte::Params::default();
                $fn(&mut term, &params);
                assert_cursor!(term, $er, $ec);
            }
        )+
    };
}

/// Table-driven macro for DECSCUSR (CSI Ps SP q) shape tests.
///
/// Pattern: `test_name : b"setup_seq" , b"target_seq" => ShapeVariant , "msg"`
/// The setup sequence moves away from the target so the assertion is meaningful.
macro_rules! test_decscusr {
    (
        $(
            $name:ident : $setup:expr , $target:expr => $shape:ident , $msg:expr
        ),+ $(,)?
    ) => {
        $(
            #[test]
            fn $name() {
                let mut term = crate::TerminalCore::new(24, 80);
                term.advance($setup);
                term.advance($target);
                assert_eq!(
                    term.dec_modes.cursor_shape,
                    crate::types::cursor::CursorShape::$shape,
                    $msg
                );
            }
        )+
    };
}
