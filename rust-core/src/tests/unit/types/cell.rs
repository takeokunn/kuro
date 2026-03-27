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
            cell.hyperlink_id(),
            Some(b.as_str()),
            "second with_hyperlink must overwrite first: a={:?} b={:?}",
            a,
            b
        );
    }
}

// -------------------------------------------------------------------------
// CellExtras allocation / deallocation
// -------------------------------------------------------------------------

#[test]
// INVARIANT: set_hyperlink_id(None) on a default cell (no extras) must be a
// no-op: no extras allocated, hyperlink_id remains None.
fn test_set_hyperlink_id_none_when_no_extras() {
    let mut cell = Cell::new('A');
    cell.set_hyperlink_id(None);
    assert_eq!(
        cell.hyperlink_id(),
        None,
        "set_hyperlink_id(None) on bare cell must leave hyperlink_id as None"
    );
    // extras must remain absent (image_id also None confirms no allocation)
    assert_eq!(cell.image_id(), None);
}

#[test]
// ALLOCATION: set_hyperlink_id(Some(...)) must allocate extras and store the id.
fn test_set_hyperlink_id_some_allocates_extras() {
    let mut cell = Cell::new('B');
    cell.set_hyperlink_id(Some("https://example.com".to_owned()));
    assert_eq!(
        cell.hyperlink_id(),
        Some("https://example.com"),
        "set_hyperlink_id(Some(...)) must store the hyperlink id"
    );
}

#[test]
// DEALLOCATION: after setting a hyperlink, clearing it while image_id is None
// must deallocate extras entirely (both accessors return None).
fn test_set_hyperlink_id_none_clears_extras_when_image_none() {
    let mut cell = Cell::new('C');
    cell.set_hyperlink_id(Some("https://example.com".to_owned()));
    // Now clear the hyperlink while image_id is still None
    cell.set_hyperlink_id(None);
    assert_eq!(
        cell.hyperlink_id(),
        None,
        "hyperlink_id must be None after clearing"
    );
    assert_eq!(
        cell.image_id(),
        None,
        "image_id must remain None (extras deallocated)"
    );
}

#[test]
// RETENTION: clearing hyperlink_id while image_id is Some must keep extras alive.
fn test_set_hyperlink_id_none_keeps_extras_when_image_some() {
    let mut cell = Cell::new('D');
    cell.set_image_id(Some(7));
    cell.set_hyperlink_id(Some("https://example.com".to_owned()));
    // Clear only the hyperlink — extras must survive because image_id is still set
    cell.set_hyperlink_id(None);
    assert_eq!(
        cell.hyperlink_id(),
        None,
        "hyperlink_id must be None after clearing"
    );
    assert_eq!(
        cell.image_id(),
        Some(7),
        "image_id must remain Some(7) — extras must not be deallocated"
    );
}

#[test]
// DEALLOCATION (symmetric): clearing image_id while hyperlink_id is None must
// deallocate extras entirely.
fn test_set_image_id_none_clears_extras_when_hyperlink_none() {
    let mut cell = Cell::new('E');
    cell.set_image_id(Some(42));
    cell.set_image_id(None);
    assert_eq!(
        cell.image_id(),
        None,
        "image_id must be None after clearing"
    );
    assert_eq!(
        cell.hyperlink_id(),
        None,
        "hyperlink_id must remain None (extras deallocated)"
    );
}

#[test]
// ALLOCATION: set_image_id(Some(...)) must allocate extras and store the id.
fn test_set_image_id_some_allocates_extras() {
    let mut cell = Cell::new('F');
    cell.set_image_id(Some(99));
    assert_eq!(
        cell.image_id(),
        Some(99),
        "set_image_id(Some(99)) must store the image id"
    );
}

#[test]
// COMBINED CLEAR: set both hyperlink_id and image_id, then clear both → no extras.
fn test_cell_with_hyperlink_and_image_both_cleared() {
    let mut cell = Cell::new('G');
    cell.set_hyperlink_id(Some("https://a.com".to_owned()));
    cell.set_image_id(Some(5));
    // Clear in reverse order: image first, then hyperlink
    cell.set_image_id(None);
    // image cleared but hyperlink still set — extras must persist
    assert_eq!(
        cell.hyperlink_id(),
        Some("https://a.com"),
        "hyperlink_id must survive clearing image_id"
    );
    cell.set_hyperlink_id(None);
    // Now both cleared
    assert_eq!(
        cell.hyperlink_id(),
        None,
        "hyperlink_id must be None after final clear"
    );
    assert_eq!(
        cell.image_id(),
        None,
        "image_id must be None after both cleared"
    );
}

// -------------------------------------------------------------------------
// Cell::new with multibyte characters
// -------------------------------------------------------------------------

#[test]
// ENCODING: Cell::new with a multi-byte UTF-8 character must store and
// retrieve it correctly via char().
fn test_cell_new_multibyte_utf8() {
    let cell = Cell::new('→'); // U+2192, 3 bytes in UTF-8
    assert_eq!(
        cell.char(),
        '→',
        "Cell::new('→') must store and return the correct char"
    );
    assert_eq!(
        cell.width,
        CellWidth::Half,
        "Cell::new must produce CellWidth::Half"
    );
}

// -------------------------------------------------------------------------
// SgrAttributes::reset idempotence (example-based complement to PBT)
// -------------------------------------------------------------------------

#[test]
// IDEMPOTENCE: reset() on an already-default SgrAttributes must be a no-op —
// the result must still equal SgrAttributes::default().
fn test_sgr_attributes_reset_idempotent() {
    let mut attrs = SgrAttributes::default();
    attrs.reset();
    assert_eq!(
        attrs,
        SgrAttributes::default(),
        "reset() on default attrs must be idempotent"
    );
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
