use super::tests_support::*;
use crate::types::Cursor;
use crate::types::CursorShape;
use proptest::prelude::*;

#[test]
fn cursor_new_sets_position_and_defaults() {
    for position in [
        DEFAULT_CURSOR_POSITION,
        Position::new(5, 10),
        Position::new(10, 5),
        Position::new(42, 7),
    ] {
        let cursor = cursor_at(position);
        assert_position(&cursor, position);
        assert_new_cursor_defaults(&cursor);
    }
}

#[test]
fn cursor_move_to_sets_absolute_position() {
    let mut cursor = cursor_at(DEFAULT_CURSOR_POSITION);
    cursor.move_to(20, 10);
    assert_position(&cursor, Position::new(20, 10));
}

#[test]
fn cursor_move_to_can_restore_saved_position() {
    let mut cursor = cursor_at(Position::new(10, 20));
    let saved = Position::new(cursor.col, cursor.row);

    cursor.move_to(99, 99);
    assert_position(&cursor, Position::new(99, 99));

    cursor.move_to(saved.col, saved.row);
    assert_position(&cursor, saved);
}

#[test]
fn cursor_move_by_applies_signed_deltas() {
    let mut cursor = cursor_at(Position::new(10, 10));

    cursor.move_by(5, -3);
    assert_position(&cursor, Position::new(15, 7));

    cursor.move_by(-20, -20);
    assert_position(&cursor, DEFAULT_CURSOR_POSITION);
}

#[test]
fn cursor_move_by_saturates_at_boundaries() {
    let mut origin = cursor_at(DEFAULT_CURSOR_POSITION);
    origin.move_by(-1000, -1000);
    assert_position(&origin, DEFAULT_CURSOR_POSITION);

    let mut max = cursor_at(Position::new(usize::MAX, usize::MAX));
    max.move_by(i32::MAX, i32::MAX);
    assert_position(&max, Position::new(usize::MAX, usize::MAX));
}

#[test]
fn cursor_shape_default_and_aliases_are_blinking_block() {
    assert_eq!(CursorShape::default(), CursorShape::BlinkingBlock);

    for value in [0i64, 1] {
        let shape = CursorShape::try_from(value).expect("DECSCUSR block value");
        assert_eq!(shape, CursorShape::BlinkingBlock);
        assert_eq!(i64::from(shape), 0, "canonical block encoding");
    }
}

#[test]
fn cursor_shape_canonical_values_roundtrip() {
    for &(value, expected_shape) in CANONICAL_SHAPES {
        let shape = CursorShape::try_from(value)
            .unwrap_or_else(|()| panic!("try_from({value}) must succeed"));
        assert_eq!(shape, expected_shape);
        assert_eq!(i64::from(shape), value);
    }
}

#[test]
fn cursor_shape_rejects_unknown_values() {
    for value in [-1i64, 7, 99] {
        assert!(
            CursorShape::try_from(value).is_err(),
            "unexpected shape for DECSCUSR {value}"
        );
    }
}

mod pbt {
    use super::*;

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(1000))]

        #[test]
        fn prop_cursor_shape_invalid_rejects_positive(v in 7i64..=1000i64) {
            prop_assert!(CursorShape::try_from(v).is_err());
        }

        #[test]
        fn prop_cursor_shape_invalid_rejects_negative(v in -1000i64..=-1i64) {
            prop_assert!(CursorShape::try_from(v).is_err());
        }

        #[test]
        fn prop_move_by_no_panic(
            col in 0usize..=10000usize,
            row in 0usize..=10000usize,
            dx  in i32::MIN..=i32::MAX,
            dy  in i32::MIN..=i32::MAX,
        ) {
            let mut cursor = Cursor::new(col, row);
            cursor.move_by(dx, dy);
            let _ = cursor.col;
            let _ = cursor.row;
        }

        #[test]
        fn prop_move_to_sets_position(
            start_col in 0usize..=1000usize,
            start_row in 0usize..=1000usize,
            dest_col  in 0usize..=1000usize,
            dest_row  in 0usize..=1000usize,
        ) {
            let mut cursor = Cursor::new(start_col, start_row);
            cursor.move_to(dest_col, dest_row);
            prop_assert_eq!(cursor.col, dest_col);
            prop_assert_eq!(cursor.row, dest_row);
        }

    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]

        #[test]
        fn prop_move_by_clamps_to_zero(
            col in 0usize..=500usize,
            row in 0usize..=500usize,
        ) {
            let mut cursor = Cursor::new(col, row);
            cursor.move_by(i32::MIN, i32::MIN);
            prop_assert_eq!(cursor.col, 0);
            prop_assert_eq!(cursor.row, 0);
        }

        #[test]
        fn prop_move_to_stores_exact_values(
            col in 0usize..=100_000usize,
            row in 0usize..=100_000usize,
        ) {
            let mut cursor = Cursor::new(0, 0);
            cursor.move_to(col, row);
            prop_assert_eq!(cursor.col, col);
            prop_assert_eq!(cursor.row, row);
        }

        #[test]
        fn prop_try_from_valid_range(v in 0i64..=6i64) {
            prop_assert!(CursorShape::try_from(v).is_ok());
        }

        #[test]
        fn prop_move_by_positive_increments(
            col in 0usize..=10_000usize,
            row in 0usize..=10_000usize,
        ) {
            let mut cursor = Cursor::new(col, row);
            cursor.move_by(1, 1);
            prop_assert_eq!(cursor.col, col + 1);
            prop_assert_eq!(cursor.row, row + 1);
        }
    }
}
