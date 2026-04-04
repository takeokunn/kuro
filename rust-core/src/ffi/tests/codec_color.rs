// -------------------------------------------------------------------------
// encode_color tests
// -------------------------------------------------------------------------

test_encode_color!(
    test_encode_color_default_is_sentinel,
    Color::Default,
    COLOR_DEFAULT_SENTINEL
);

test_encode_color!(
    test_encode_color_rgb_true_black_is_zero,
    Color::Rgb(0, 0, 0),
    0u32
);

test_encode_color!(
    test_encode_color_named_red,
    Color::Named(NamedColor::Red),
    COLOR_NAMED_MARKER | 1u32
);

test_encode_color!(
    test_encode_color_indexed,
    Color::Indexed(16),
    COLOR_INDEXED_MARKER | 16u32
);

test_encode_color!(
    test_encode_color_indexed_zero,
    Color::Indexed(0),
    COLOR_INDEXED_MARKER
);

test_encode_color!(
    test_encode_color_indexed_255,
    Color::Indexed(255),
    0x4000_00FFu32
);

// -------------------------------------------------------------------------
// Named color boundary tests (Black=0, White=7, BrightBlack=8, BrightWhite=15)
// -------------------------------------------------------------------------

test_encode_color!(
    test_encode_color_named_black_boundary,
    Color::Named(NamedColor::Black),
    COLOR_NAMED_MARKER
);

test_encode_color!(
    test_encode_color_named_white_boundary,
    Color::Named(NamedColor::White),
    COLOR_NAMED_MARKER | 7u32
);

test_encode_color!(
    test_encode_color_named_bright_black_boundary,
    Color::Named(NamedColor::BrightBlack),
    COLOR_NAMED_MARKER | 8u32
);

// -------------------------------------------------------------------------
// RGB single-channel boundary tests
// -------------------------------------------------------------------------

test_encode_color!(
    test_encode_color_rgb_single_channel_red,
    Color::Rgb(255, 0, 0),
    0x00FF_0000
);

test_encode_color!(
    test_encode_color_rgb_single_channel_green,
    Color::Rgb(0, 255, 0),
    0x0000_FF00
);

test_encode_color!(
    test_encode_color_rgb_single_channel_blue,
    Color::Rgb(0, 0, 255),
    0x0000_00FF
);

// -------------------------------------------------------------------------
// encode_attrs: flag-bit tests via macro
// -------------------------------------------------------------------------

test_encode_attrs!(
    encode_attrs_bold_sets_bit_0,
    attrs_flags!(SgrFlags::BOLD),
    shift 0,
    mask 0x1,
    eq 1u64
);

test_encode_attrs!(
    encode_attrs_underline_curly_encodes_style_3,
    attrs_underline!(UnderlineStyle::Curly),
    shift 9,
    mask 0x7,
    eq 3u64
);

test_encode_attrs!(
    encode_attrs_underline_double_encodes_style_2,
    attrs_underline!(UnderlineStyle::Double),
    shift 9,
    mask 0x7,
    eq 2u64
);

test_encode_attrs!(
    encode_attrs_underline_dotted_encodes_style_4,
    attrs_underline!(UnderlineStyle::Dotted),
    shift 9,
    mask 0x7,
    eq 4u64
);

test_encode_attrs!(
    encode_attrs_underline_dashed_encodes_style_5,
    attrs_underline!(UnderlineStyle::Dashed),
    shift 9,
    mask 0x7,
    eq 5u64
);

test_encode_attrs!(
    encode_attrs_underline_none_encodes_style_0,
    attrs_underline!(UnderlineStyle::None),
    shift 9,
    mask 0x7,
    eq 0u64
);

// -------------------------------------------------------------------------
// Remaining encode_color tests (structural variants that don't fit the macro)
// -------------------------------------------------------------------------

#[test]
fn test_named_colors_are_unique() {
    use std::collections::HashSet;
    let colors = [
        NamedColor::Black,
        NamedColor::Red,
        NamedColor::Green,
        NamedColor::Yellow,
        NamedColor::Blue,
        NamedColor::Magenta,
        NamedColor::Cyan,
        NamedColor::White,
        NamedColor::BrightBlack,
        NamedColor::BrightRed,
        NamedColor::BrightGreen,
        NamedColor::BrightYellow,
        NamedColor::BrightBlue,
        NamedColor::BrightMagenta,
        NamedColor::BrightCyan,
        NamedColor::BrightWhite,
    ];
    let encoded: HashSet<u32> = colors
        .iter()
        .map(|c| encode_color(&Color::Named(*c)))
        .collect();
    assert_eq!(
        encoded.len(),
        16,
        "all 16 named colors must have unique encodings"
    );
}

/// `Color::Named(BrightWhite)` (index 15, the highest named-color index) must
/// encode distinctly from all other named colors and from any indexed color.
#[test]
fn test_encode_color_named_bright_white_index_15() {
    let encoded = encode_color(&Color::Named(NamedColor::BrightWhite));
    // BrightWhite is repr(u8) == 15
    assert_eq!(
        encoded,
        COLOR_NAMED_MARKER | 15u32,
        "BrightWhite must encode to COLOR_NAMED_MARKER | 15"
    );
    // Must differ from Indexed(15) which uses the indexed marker.
    assert_ne!(
        encoded,
        COLOR_INDEXED_MARKER | 15u32,
        "Named(BrightWhite) must not collide with Indexed(15)"
    );
}

// -------------------------------------------------------------------------
// Additional encode_color tests (Round 35) — named, indexed, RGB, default
// -------------------------------------------------------------------------

// Named color 8: BrightBlack — first bright variant (index 8).
test_encode_color!(
    test_encode_color_named_bright_black_is_8,
    Color::Named(NamedColor::BrightBlack),
    COLOR_NAMED_MARKER | 8u32
);

// Named color 14: BrightCyan (index 14).
test_encode_color!(
    test_encode_color_named_bright_cyan_is_14,
    Color::Named(NamedColor::BrightCyan),
    COLOR_NAMED_MARKER | 14u32
);

// Named color 15: BrightWhite (index 15, the highest named index).
test_encode_color!(
    test_encode_color_named_bright_white_is_15,
    Color::Named(NamedColor::BrightWhite),
    COLOR_NAMED_MARKER | 15u32
);

// Indexed color 127: mid-range indexed color.
test_encode_color!(
    test_encode_color_indexed_127,
    Color::Indexed(127),
    COLOR_INDEXED_MARKER | 127u32
);

// Indexed color 128: one past mid-point — must not collide with 127.
test_encode_color!(
    test_encode_color_indexed_128,
    Color::Indexed(128),
    COLOR_INDEXED_MARKER | 128u32
);

// RGB (0, 0, 0): true black — lower 24 bits all zero, no marker bits.
test_encode_color!(
    test_encode_color_rgb_black_is_zero,
    Color::Rgb(0, 0, 0),
    0u32
);

// RGB (255, 255, 255): true white — lower 24 bits all one, no marker bits.
test_encode_color!(
    test_encode_color_rgb_white_is_0x00ffffff,
    Color::Rgb(255, 255, 255),
    0x00FF_FFFFu32
);

// Color::Default sentinel value via macro.
test_encode_color!(
    test_encode_color_default_sentinel_via_macro,
    Color::Default,
    COLOR_DEFAULT_SENTINEL
);

/// `encode_color` for `Color::Rgb(255, 255, 255)` (true white) must produce
/// `0x00FFFFFF` with no marker bits set — this is the maximum RGB value and
/// must not be confused with any sentinel or named-color encoding.
#[test]
fn test_encode_color_rgb_true_white_no_marker_bits() {
    let encoded = encode_color(&Color::Rgb(255, 255, 255));
    assert_eq!(
        encoded, COLOR_RGB_MASK,
        "Rgb(255,255,255) must be 0x00FFFFFF"
    );
    // Must not have named-color marker (bit 31).
    assert_eq!(
        encoded & COLOR_NAMED_MARKER,
        0,
        "true white must not set bit 31"
    );
    // Must not have indexed-color marker (bit 30).
    assert_eq!(
        encoded & COLOR_INDEXED_MARKER,
        0,
        "true white must not set bit 30"
    );
    // Must not equal the default sentinel.
    assert_ne!(
        encoded, COLOR_DEFAULT_SENTINEL,
        "true white must not equal default sentinel"
    );
}
