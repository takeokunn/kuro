//! Unit tests for Kitty Unicode-placeholder decoding.
//!
//! Module under test: `grid/placeholder.rs`

use super::*;
use crate::types::color::Color;

/// Build a placeholder grapheme: base U+10EEEE + the given diacritics (by index
/// into the rowcolumn table).
fn placeholder_grapheme(diacritic_indices: &[usize]) -> String {
    let mut s = String::new();
    s.push(PLACEHOLDER_CHAR);
    for &i in diacritic_indices {
        s.push(ROWCOLUMN_DIACRITICS[i]);
    }
    s
}

// --- table sanity ---

/// INTENT: the embedded diacritic table is exactly kitty's published 297 entries.
#[test]
fn rowcolumn_table_has_297_entries() {
    assert_eq!(ROWCOLUMN_DIACRITICS.len(), 297);
}

/// INTENT: the first three table entries match kitty's documented values
/// (U+0305=0, U+030D=1, U+030E=2).
#[test]
fn rowcolumn_table_known_prefix() {
    assert_eq!(ROWCOLUMN_DIACRITICS[0], '\u{0305}');
    assert_eq!(ROWCOLUMN_DIACRITICS[1], '\u{030D}');
    assert_eq!(ROWCOLUMN_DIACRITICS[2], '\u{030E}');
}

/// INTENT: every table entry decodes back to its own index.
#[test]
fn diacritic_value_roundtrips_every_entry() {
    for (i, &c) in ROWCOLUMN_DIACRITICS.iter().enumerate() {
        assert_eq!(diacritic_value(c), Some(i as u32), "entry {i} ({c:?})");
    }
}

/// INTENT: a non-diacritic char decodes to None.
#[test]
fn diacritic_value_rejects_non_diacritic() {
    assert_eq!(diacritic_value('A'), None);
    assert_eq!(diacritic_value('\u{0301}'), None); // a combining accent NOT in the table
}

// --- color decoding ---

/// INTENT: a truecolor foreground encodes the id directly as 0xRRGGBB.
#[test]
fn image_id_from_truecolor_fg() {
    assert_eq!(
        image_id_from_color(Color::Rgb(0x12, 0x34, 0x56)),
        Some(0x0012_3456)
    );
}

/// INTENT: a 256-color (indexed) foreground encodes a small id 0..=255.
#[test]
fn image_id_from_indexed_fg() {
    assert_eq!(image_id_from_color(Color::Indexed(200)), Some(200));
}

/// INTENT: a default foreground encodes no id (malformed placeholder).
#[test]
fn image_id_from_default_fg_is_none() {
    assert_eq!(image_id_from_color(Color::Default), None);
}

/// INTENT: an id of 0 (e.g. fg = pure black truecolor) is treated as "no id".
#[test]
fn image_id_zero_is_none() {
    assert_eq!(image_id_from_color(Color::Rgb(0, 0, 0)), None);
}

/// INTENT: the underline color supplies the placement id; default = None.
#[test]
fn placement_id_from_underline_color() {
    assert_eq!(placement_id_from_color(Color::Indexed(7)), Some(7));
    assert_eq!(
        placement_id_from_color(Color::Rgb(0, 1, 0)),
        Some(0x0000_0100)
    );
    assert_eq!(placement_id_from_color(Color::Default), None);
}

// --- full placeholder decoding ---

/// INTENT: a placeholder with no diacritics decodes id from fg, row/col = 0.
#[test]
fn decode_placeholder_no_diacritics() {
    let g = placeholder_grapheme(&[]);
    let info = decode_placeholder(&g, Color::Rgb(0, 0, 5), Color::Default).expect("decodes");
    assert_eq!(info.image_id, 5);
    assert_eq!(info.img_row, 0);
    assert_eq!(info.img_col, 0);
    assert_eq!(info.placement_id, None);
}

/// INTENT: the 1st diacritic decodes to row, the 2nd to column.
#[test]
fn decode_placeholder_row_col_from_diacritics() {
    // index 3 = row, index 9 = column
    let g = placeholder_grapheme(&[3, 9]);
    let info = decode_placeholder(&g, Color::Indexed(42), Color::Default).expect("decodes");
    assert_eq!(info.image_id, 42);
    assert_eq!(info.img_row, 3);
    assert_eq!(info.img_col, 9);
}

/// INTENT: a 3rd diacritic supplies the high byte of the image id.
#[test]
fn decode_placeholder_high_byte_extension() {
    // row=0, col=0, extra=2 → id |= (2 << 24)
    let g = placeholder_grapheme(&[0, 0, 2]);
    let info = decode_placeholder(&g, Color::Rgb(0x00, 0x00, 0x01), Color::Default).expect("decodes");
    assert_eq!(info.image_id, (2u32 << 24) | 1);
}

/// INTENT: the underline color is decoded as the placement id.
#[test]
fn decode_placeholder_placement_id_from_underline() {
    let g = placeholder_grapheme(&[]);
    let info = decode_placeholder(&g, Color::Indexed(9), Color::Indexed(3)).expect("decodes");
    assert_eq!(info.placement_id, Some(3));
}

/// INTENT: a malformed placeholder (no fg id) is ignored entirely.
#[test]
fn decode_placeholder_without_fg_id_is_ignored() {
    let g = placeholder_grapheme(&[3, 9]);
    assert_eq!(decode_placeholder(&g, Color::Default, Color::Default), None);
}

/// INTENT: a non-placeholder grapheme is rejected.
#[test]
fn decode_placeholder_rejects_non_placeholder() {
    assert_eq!(
        decode_placeholder("A", Color::Indexed(1), Color::Default),
        None
    );
}

/// INTENT: a Named (16-color) foreground encodes a tiny id via palette index.
#[test]
fn decode_placeholder_named_fg() {
    use crate::types::color::NamedColor;
    let g = placeholder_grapheme(&[]);
    let info =
        decode_placeholder(&g, Color::Named(NamedColor::BrightBlack), Color::Default).expect("ok");
    assert_eq!(info.image_id, 8);
}

// --- adversarial: malformed / boundary placeholders ---

/// INTENT: a placeholder cell whose foreground encodes no id (default color) is
/// ignored even when valid row/col diacritics are present.
#[test]
fn decode_placeholder_no_fg_with_diacritics_is_ignored() {
    let g = placeholder_grapheme(&[5, 7]);
    assert_eq!(decode_placeholder(&g, Color::Default, Color::Default), None);
}

/// INTENT: a trailing char that is NOT a rowcolumn diacritic decodes as row 0
/// (the unknown combining char contributes no value) and never panics.
#[test]
fn decode_placeholder_unknown_diacritic_yields_zero_row() {
    let mut g = String::new();
    g.push(PLACEHOLDER_CHAR);
    g.push('a'); // not a rowcolumn diacritic
    let info = decode_placeholder(&g, Color::Rgb(0, 0, 1), Color::Default).expect("ok");
    assert_eq!(info.img_row, 0);
    assert_eq!(info.img_col, 0);
    assert_eq!(info.image_id, 1);
}

/// INTENT: the 3rd diacritic (high-byte extension) is masked to a single byte —
/// a diacritic index > 255 must NOT corrupt the lower 24 bits of the id, and the
/// decode is bounded (no panic / no silent bit-drop into low bits).
#[test]
fn decode_placeholder_high_byte_masks_to_one_byte() {
    // Pick a high-byte diacritic with index 296 (> 255). Masked: 296 & 0xFF = 40.
    let g = placeholder_grapheme(&[0, 0, 296]);
    let info = decode_placeholder(&g, Color::Rgb(0x00, 0x00, 0x01), Color::Default).expect("ok");
    // id = 0x000001 | ((296 & 0xFF) << 24) = 0x000001 | (40 << 24) = 0x28000001.
    assert_eq!(info.image_id, 0x0000_0001 | (40u32 << 24));
    // Lower 24 bits (the truecolor id) are preserved intact.
    assert_eq!(info.image_id & 0x00FF_FFFF, 0x0000_0001);
}

/// INTENT: a valid 3-diacritic placeholder with a small high byte composes the
/// 32-bit id as `(low24) | (highbyte << 24)`.
#[test]
fn decode_placeholder_high_byte_small_value() {
    // 3rd diacritic index 2 → high byte 2.
    let g = placeholder_grapheme(&[1, 1, 2]);
    let info = decode_placeholder(&g, Color::Rgb(0x12, 0x34, 0x56), Color::Default).expect("ok");
    assert_eq!(info.image_id, 0x0212_3456);
    assert_eq!(info.img_row, 1);
    assert_eq!(info.img_col, 1);
}
