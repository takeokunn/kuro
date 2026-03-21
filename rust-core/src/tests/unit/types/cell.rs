//! Property-based tests for `crate::types::cell` (Cell, `SgrAttributes`, `CellWidth`, `UnderlineStyle`)
//!
//! Tests in this file complement the embedded `#[cfg(test)]` tests in
//! `src/types/cell.rs` and add property-based coverage for mathematical
//! invariants and boundary conditions.

use crate::types::cell::{Cell, CellWidth, SgrAttributes, SgrFlags, UnderlineStyle};
use crate::types::color::Color;
use proptest::prelude::*;

// -------------------------------------------------------------------------
// Arbitrary generators
// -------------------------------------------------------------------------

prop_compose! {
    /// Generate an SgrAttributes with randomised boolean fields.
    /// Colors remain at their defaults to keep generation simple; colour
    /// property tests live in types/color.rs.
    fn arb_sgr_attrs()(
        bold        in proptest::bool::ANY,
        dim         in proptest::bool::ANY,
        italic      in proptest::bool::ANY,
        blink_slow  in proptest::bool::ANY,
        blink_fast  in proptest::bool::ANY,
        inverse     in proptest::bool::ANY,
        hidden      in proptest::bool::ANY,
        strikethrough in proptest::bool::ANY,
    ) -> SgrAttributes {
        let mut flags = SgrFlags::empty();
        flags.set(SgrFlags::BOLD, bold);
        flags.set(SgrFlags::DIM, dim);
        flags.set(SgrFlags::ITALIC, italic);
        flags.set(SgrFlags::BLINK_SLOW, blink_slow);
        flags.set(SgrFlags::BLINK_FAST, blink_fast);
        flags.set(SgrFlags::INVERSE, inverse);
        flags.set(SgrFlags::HIDDEN, hidden);
        flags.set(SgrFlags::STRIKETHROUGH, strikethrough);
        SgrAttributes { flags, ..Default::default() }
    }
}

/// Strategy that picks one of the six `UnderlineStyle` variants.
fn arb_underline_style() -> impl Strategy<Value = UnderlineStyle> {
    prop_oneof![
        Just(UnderlineStyle::None),
        Just(UnderlineStyle::Straight),
        Just(UnderlineStyle::Double),
        Just(UnderlineStyle::Curly),
        Just(UnderlineStyle::Dotted),
        Just(UnderlineStyle::Dashed),
    ]
}

// -------------------------------------------------------------------------
// Property-based tests
// -------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(500))]

    #[test]
    // IDEMPOTENCE: Resetting SgrAttributes twice produces the same result as
    // resetting once — and that result must equal SgrAttributes::default().
    fn prop_sgr_reset_idempotent(mut attrs in arb_sgr_attrs()) {
        attrs.reset();
        let after_first = attrs;
        attrs.reset();
        let after_second = attrs;
        prop_assert_eq!(after_first, SgrAttributes::default());
        prop_assert_eq!(after_second, SgrAttributes::default());
        prop_assert_eq!(after_first, after_second);
    }

    #[test]
    // BOUNDARY: push_combining enforces a 32-byte grapheme cap.  After pushing
    // an arbitrary number of combining characters from U+0300–U+036F (each is
    // 2 bytes in UTF-8), the grapheme string must never exceed 32 bytes.
    fn prop_push_combining_32_byte_cap(
        count in 0usize..=50usize,
        combining in proptest::collection::vec(
            prop::char::range('\u{0300}', '\u{036F}'),
            0..=50,
        )
    ) {
        let mut cell = Cell::new('a');
        for c in combining.iter().take(count) {
            cell.push_combining(*c);
        }
        prop_assert!(
            cell.grapheme.len() <= 32,
            "grapheme exceeded 32 bytes: len={}",
            cell.grapheme.len()
        );
    }

    #[test]
    // INVARIANT: attrs.underline() must return true iff underline_style != None.
    fn prop_underline_helper_consistent(style in arb_underline_style()) {
        let attrs = SgrAttributes {
            underline_style: style,
            ..Default::default()
        };
        let expected = style != UnderlineStyle::None;
        prop_assert_eq!(
            attrs.underline(),
            expected,
            "underline() must be true iff style != None (style={:?})",
            style
        );
    }

    #[test]
    // INVARIANT: Cell::new(c) always sets width == CellWidth::Half.
    // (Wide-char cells are constructed explicitly by the screen layer, not here.)
    fn prop_cell_new_width_is_half(c in prop::char::range('\u{0020}', '\u{007E}')) {
        let cell = Cell::new(c);
        prop_assert_eq!(
            cell.width,
            CellWidth::Half,
            "Cell::new must always produce CellWidth::Half, got {:?}",
            c
        );
    }

    #[test]
    // CHAINING: After calling with_hyperlink(a) and then with_hyperlink(b),
    // the cell must retain only the last hyperlink id (b).
    fn prop_hyperlink_replaces_previous(
        a in "[a-z]{1,20}",
        b in "[a-z]{1,20}",
    ) {
        let cell = Cell::new('X')
            .with_hyperlink(a.clone())
            .with_hyperlink(b.clone());
        prop_assert_eq!(
            cell.hyperlink_id,
            Some(b.clone()),
            "second with_hyperlink must overwrite first: a={:?} b={:?}",
            a,
            b
        );
    }
}

// -------------------------------------------------------------------------
// Example-based tests (exhaustive enumeration where PBT is awkward)
// -------------------------------------------------------------------------

#[test]
// MAPPING: Each UnderlineStyle variant must produce the correct underline()
// boolean.  None → false; all others → true.
fn underline_style_all_variants_correct_bool() {
    let cases: &[(UnderlineStyle, bool)] = &[
        (UnderlineStyle::None, false),
        (UnderlineStyle::Straight, true),
        (UnderlineStyle::Double, true),
        (UnderlineStyle::Curly, true),
        (UnderlineStyle::Dotted, true),
        (UnderlineStyle::Dashed, true),
    ];
    for (style, expected) in cases {
        let attrs = SgrAttributes {
            underline_style: *style,
            ..Default::default()
        };
        assert_eq!(
            attrs.underline(),
            *expected,
            "underline() wrong for {style:?}: expected {expected}"
        );
    }
}

#[test]
// INVARIANT: SgrAttributes::default() must have all booleans false and
// both color fields equal to Color::Default.
fn sgr_default_all_false() {
    let attrs = SgrAttributes::default();
    assert_eq!(
        attrs.flags,
        SgrFlags::empty(),
        "all boolean flags must be clear in default attrs"
    );
    assert!(!attrs.underline());
    assert_eq!(attrs.underline_style, UnderlineStyle::None);
    assert_eq!(attrs.foreground, Color::Default);
    assert_eq!(attrs.background, Color::Default);
}
