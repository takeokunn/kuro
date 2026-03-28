// -------------------------------------------------------------------------
// encode_attrs tests
// -------------------------------------------------------------------------

#[test]
fn test_encode_attrs_default_is_zero() {
    assert_eq!(encode_attrs(&SgrAttributes::default()), 0u64);
}

#[test]
fn test_encode_attrs_bold() {
    assert_eq!(encode_attrs(&attrs_flags!(SgrFlags::BOLD)), 0x1u64);
}

#[test]
fn test_encode_attrs_all_flags_set() {
    let attrs = SgrAttributes {
        foreground: Color::Default,
        background: Color::Default,
        flags: SgrFlags::BOLD
            | SgrFlags::DIM
            | SgrFlags::ITALIC
            | SgrFlags::BLINK_SLOW
            | SgrFlags::BLINK_FAST
            | SgrFlags::INVERSE
            | SgrFlags::HIDDEN
            | SgrFlags::STRIKETHROUGH,
        underline_style: UnderlineStyle::Straight,
        underline_color: Color::Default,
    };
    let result = encode_attrs(&attrs);
    // All 9 flag bits plus underline-style=1 in bits 9-11 must be set
    assert_eq!(result & 0x1FF, 0x1FFu64, "all 9 flag bits must be set");
    assert_ne!(result, 0);
}

// -------------------------------------------------------------------------
// encode_attrs boundary tests
// -------------------------------------------------------------------------

#[test]
fn encode_attrs_underline_straight_sets_bit_3_and_style_bits_9_11() {
    let bits = encode_attrs(&attrs_underline!(UnderlineStyle::Straight));
    assert_eq!(bits & 0x008, 0x008, "underline flag must set bit 3");
    let style = (bits >> 9) & 0x7;
    assert_eq!(
        style, 1,
        "Straight underline style must encode to 1 in bits 9-11"
    );
}

/// All underline styles encode to their correct 3-bit style fields.
#[test]
fn encode_attrs_all_underline_styles_correct() {
    let cases: &[(UnderlineStyle, u64)] = &[
        (UnderlineStyle::None, 0),
        (UnderlineStyle::Straight, 1),
        (UnderlineStyle::Double, 2),
        (UnderlineStyle::Curly, 3),
        (UnderlineStyle::Dotted, 4),
        (UnderlineStyle::Dashed, 5),
    ];
    for &(style, expected) in cases {
        let bits = encode_attrs(&attrs_underline!(style));
        let encoded = (bits >> 9) & 0x7;
        assert_eq!(
            encoded, expected,
            "underline style {:?} must encode to {expected}",
            style
        );
    }
}

/// Maximum SGR combination: all flags + Curly underline + underline color produces non-zero, sane bits.
#[test]
fn encode_attrs_max_combination_non_zero() {
    use crate::types::color::Color;
    let attrs = SgrAttributes {
        foreground: Color::Rgb(255, 0, 0),
        background: Color::Rgb(0, 0, 255),
        flags: SgrFlags::BOLD
            | SgrFlags::DIM
            | SgrFlags::ITALIC
            | SgrFlags::BLINK_SLOW
            | SgrFlags::BLINK_FAST
            | SgrFlags::INVERSE
            | SgrFlags::HIDDEN
            | SgrFlags::STRIKETHROUGH,
        underline_style: UnderlineStyle::Curly,
        underline_color: Color::Rgb(0, 255, 0),
    };
    let bits = encode_attrs(&attrs);
    // All 9 flag bits (0x1FF) must be set
    assert_eq!(bits & 0x1FF, 0x1FF, "all 9 flag bits must be set");
    // Underline style = 3 (Curly) in bits 9-11
    assert_eq!((bits >> 9) & 0x7, 3, "Curly style must encode in bits 9-11");
}

/// Each individual SGR flag bit occupies a distinct position (no overlap).
#[test]
fn encode_attrs_flag_bits_are_distinct() {
    let all_flags = [
        SgrFlags::BOLD,
        SgrFlags::DIM,
        SgrFlags::ITALIC,
        SgrFlags::BLINK_SLOW,
        SgrFlags::BLINK_FAST,
        SgrFlags::INVERSE,
        SgrFlags::HIDDEN,
        SgrFlags::STRIKETHROUGH,
    ];
    let encoded: Vec<u64> = all_flags
        .iter()
        .map(|&f| encode_attrs(&attrs_flags!(f)))
        .collect();
    // All values must be unique (each flag maps to exactly one bit).
    let unique: std::collections::HashSet<u64> = encoded.iter().copied().collect();
    assert_eq!(
        unique.len(),
        all_flags.len(),
        "every SGR flag must encode to a distinct bit"
    );
    // Each must be a power of two (single bit set).
    for bits in &encoded {
        assert!(
            bits.count_ones() == 1,
            "each single-flag encoding must be a power of two, got {bits:#x}"
        );
    }
}

#[test]
fn encode_attrs_wide_char_col_to_buf_via_encode_line() {
    // Verify that a line with a wide char placeholder produces non-empty col_to_buf.
    let wide_cell = Cell::new('\u{30C6}'); // テ
    let placeholder = Cell {
        width: CellWidth::Wide,
        grapheme: CompactString::new(" "),
        ..Default::default()
    };
    let cells = vec![wide_cell, placeholder];
    let (_, _, col_to_buf) = encode_line(&cells);
    assert!(
        !col_to_buf.is_empty(),
        "wide char line must produce non-empty col_to_buf"
    );
}

/// `encode_attrs` with no underline style but a non-default underline color
/// must NOT set `ATTRS_UNDERLINE_BIT` — the underline flag only reflects style,
/// not the mere presence of a color.
#[test]
fn encode_attrs_underline_bit_not_set_for_color_only() {
    let attrs = SgrAttributes {
        underline_color: Color::Rgb(255, 128, 0),
        underline_style: UnderlineStyle::None,
        ..Default::default()
    };
    let bits = encode_attrs(&attrs);
    assert_eq!(
        bits & ATTRS_UNDERLINE_BIT,
        0,
        "ATTRS_UNDERLINE_BIT must be clear when underline_style is None, even with a color set"
    );
}

// -------------------------------------------------------------------------
// Additional encode_attrs tests (Round 35) — individual flags + combined
// -------------------------------------------------------------------------

// Italic only: SgrFlags::ITALIC is raw bit 2; maps directly to encode bit 2 (0x4).
test_encode_attrs!(
    encode_attrs_italic_only_sets_bit_2,
    attrs_flags!(SgrFlags::ITALIC),
    shift 2,
    mask 0x1,
    eq 1u64
);

// Underline only (Straight style): sets ATTRS_UNDERLINE_BIT (bit 3 = 0x8).
test_encode_attrs!(
    encode_attrs_underline_straight_sets_underline_bit,
    attrs_underline!(UnderlineStyle::Straight),
    shift 3,
    mask 0x1,
    eq 1u64
);

// Blink (slow) only: SgrFlags::BLINK_SLOW is raw bit 3; maps to encode bit 4 (0x10).
test_encode_attrs!(
    encode_attrs_blink_slow_sets_bit_4,
    attrs_flags!(SgrFlags::BLINK_SLOW),
    shift 4,
    mask 0x1,
    eq 1u64
);

// Blink (rapid/fast) only: SgrFlags::BLINK_FAST is raw bit 4; maps to encode bit 5 (0x20).
test_encode_attrs!(
    encode_attrs_blink_fast_sets_bit_5,
    attrs_flags!(SgrFlags::BLINK_FAST),
    shift 5,
    mask 0x1,
    eq 1u64
);

// Crossed-out (strikethrough) only: SgrFlags::STRIKETHROUGH is raw bit 7; maps to encode bit 8 (0x100).
test_encode_attrs!(
    encode_attrs_strikethrough_sets_bit_8,
    attrs_flags!(SgrFlags::STRIKETHROUGH),
    shift 8,
    mask 0x1,
    eq 1u64
);

// Inverse only: SgrFlags::INVERSE is raw bit 5; maps to encode bit 6 (0x40).
test_encode_attrs!(
    encode_attrs_inverse_sets_bit_6,
    attrs_flags!(SgrFlags::INVERSE),
    shift 6,
    mask 0x1,
    eq 1u64
);

// Bold + italic + underline (Straight) combined: bits 0 (bold), 2 (italic), 3 (underline) → 0xD.
test_encode_attrs!(
    encode_attrs_bold_italic_underline_combined,
    SgrAttributes {
        flags: SgrFlags::BOLD | SgrFlags::ITALIC,
        underline_style: UnderlineStyle::Straight,
        ..Default::default()
    },
    shift 0,
    mask 0xF,
    eq 0xDu64
);
