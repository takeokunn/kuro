use super::tests_support::arb_cell;
use crate::ffi::abstraction::tests_unit::make_session;
use super::super::TerminalSession;
use crate::types::cell::CellWidth;
use proptest::prelude::*;

// ---------------------------------------------------------------------------
// B-1: Property-based tests with proptest
// ---------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]
    /// Property: encode_line_faces must never panic with arbitrary cell slices.
    #[test]
    fn prop_encode_line_faces_no_panic(cells in prop::collection::vec(arb_cell(), 0..=80)) {
        let _ = TerminalSession::encode_line_faces(0, &cells);
    }
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]
    #[test]
    fn prop_encode_line_faces_coverage_invariant(
        cells in proptest::collection::vec(arb_cell(), 1..=80usize),
    ) {
        let (_row, _text, face_ranges, _col_to_buf) = TerminalSession::encode_line_faces(0, &cells);

        let non_placeholder_count = cells.iter().filter(|c| {
            !(c.width == CellWidth::Wide && c.grapheme.as_str() == " ")
        }).count();
        if non_placeholder_count > 0 {
            prop_assert!(!face_ranges.is_empty(),
                "encode_line_faces returned empty vec for {} non-placeholder cells", non_placeholder_count);
        }

        if !face_ranges.is_empty() {
            prop_assert_eq!(face_ranges[0].0, 0,
                "First range must start at 0, got {}", face_ranges[0].0);

            let last = face_ranges.last().unwrap();
            prop_assert_eq!(last.1, non_placeholder_count,
                "Last range must end at {}, got {}", non_placeholder_count, last.1);

            for window in face_ranges.windows(2) {
                prop_assert_eq!(window[0].1, window[1].0,
                    "Gap/overlap between ranges: first ends at {}, next starts at {}",
                    window[0].1, window[1].0);
            }

            for (start, end, _, _, _, _) in &face_ranges {
                prop_assert!(start < end,
                    "Empty range found: start={}, end={}", start, end);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// FR-007: SGR → Cell → FFI integration roundtrip tests
// ---------------------------------------------------------------------------

#[test]
fn test_integration_bold_rgb_fg() {
    let mut session = make_session();
    session.core.advance(b"\x1b[1;38;2;255;0;128mX");
    let results = session.get_dirty_lines_with_faces();

    assert!(!results.is_empty(), "Expected dirty lines after advancing");
    let (_row, text, face_ranges, _col_to_buf) = &results[0];
    assert_eq!(text.trim_end(), "X");
    assert!(!face_ranges.is_empty());

    let (start, end, fg, bg, flags, _ul_color) = face_ranges[0];
    assert_eq!(start, 0);
    assert_eq!(end, 1);
    assert_eq!(
        fg, 0x00FF_0080u32,
        "fg should be Rgb(255,0,128) = 0x00FF0080"
    );
    assert_eq!(
        bg, 0xFF00_0000u32,
        "bg should be Default sentinel = 0xFF00_0000"
    );
    assert_eq!(flags, 0x01u64, "flags should have bold bit set (0x01)");
}

#[test]
fn test_integration_named_color_red() {
    let mut session = make_session();
    session.core.advance(b"\x1b[31mA");
    let results = session.get_dirty_lines_with_faces();

    assert!(!results.is_empty());
    let (_row, text, face_ranges, _col_to_buf) = &results[0];
    assert!(text.contains('A'));
    assert!(!face_ranges.is_empty());

    let (start, end, fg, _bg, _flags, _ul_color) = face_ranges[0];
    assert_eq!(start, 0);
    assert_eq!(end, 1);
    assert_eq!(fg, 0x8000_0001u32, "Named(Red) should encode as 0x80000001");
}

#[test]
fn test_integration_indexed_color() {
    let mut session = make_session();
    session.core.advance(b"\x1b[38;5;42mB");
    let results = session.get_dirty_lines_with_faces();

    assert!(!results.is_empty());
    let (_row, text, face_ranges, _col_to_buf) = &results[0];
    assert!(text.contains('B'));
    assert!(!face_ranges.is_empty());

    let (_, _, fg, _, _, _) = face_ranges[0];
    assert_eq!(
        fg, 0x4000_002Au32,
        "Indexed(42) should encode as 0x4000002A"
    );
}

#[test]
fn test_integration_true_black_vs_default() {
    let mut session = make_session();
    session.core.advance(b"\x1b[38;2;0;0;0mC");
    let results = session.get_dirty_lines_with_faces();

    assert!(!results.is_empty());
    let (_row, _text, face_ranges, _col_to_buf) = &results[0];
    assert!(!face_ranges.is_empty());

    let (_, _, fg, bg, _, _) = face_ranges[0];
    assert_eq!(fg, 0u32, "Rgb(0,0,0) must encode as 0 (true black)");
    assert_eq!(
        bg, 0xFF00_0000u32,
        "Default bg should encode as 0xFF00_0000"
    );
}

#[test]
fn test_integration_default_color_sentinel() {
    let mut session = make_session();
    session.core.advance(b"D");
    let results = session.get_dirty_lines_with_faces();

    assert!(!results.is_empty());
    let (_row, _text, face_ranges, _col_to_buf) = &results[0];
    assert!(!face_ranges.is_empty());

    let (_, _, fg, bg, flags, _ul_color) = face_ranges[0];
    assert_eq!(
        fg, 0xFF00_0000u32,
        "Default fg should be 0xFF00_0000 sentinel"
    );
    assert_eq!(
        bg, 0xFF00_0000u32,
        "Default bg should be 0xFF00_0000 sentinel"
    );
    assert_eq!(flags, 0u64, "No attributes set");
}
