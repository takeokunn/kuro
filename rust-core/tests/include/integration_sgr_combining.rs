// ─────────────────────────────────────────────────────────────────────────────
// SGR combining attributes — bold + italic + underline + color
// ─────────────────────────────────────────────────────────────────────────────

// SGR bold + italic + underline + RGB foreground in one sequence must all be set.
#[test]
fn sgr_combined_bold_italic_underline_rgb_fg() {
    let mut t = TerminalCore::new(24, 80);
    // bold=1, italic=3, underline=4, then 38;2;255;0;128 for fg
    t.advance(b"\x1b[1;3;4;38;2;255;0;128m");
    assert!(t.current_bold(), "bold must be set");
    assert!(t.current_italic(), "italic must be set");
    assert!(t.current_underline(), "underline must be set");
    assert_eq!(
        *t.current_foreground(),
        kuro_core::Color::Rgb(255, 0, 128),
        "RGB foreground must be set"
    );
}

// SGR blink-fast (6) sets the BLINK_FAST flag; SGR 0 clears it.
#[test]
fn sgr_6_blink_fast_set_and_cleared_by_reset() {
    use kuro_core::types::cell::SgrFlags;
    assert_flag_set_clear!(b"\x1b[6m", b"\x1b[0m", SgrFlags::BLINK_FAST, "BLINK_FAST");
}

// SGR dim (2) sets the DIM flag; SGR 22 clears it (not SGR 0 only).
#[test]
fn sgr_2_dim_set_and_sgr_22_clears_it() {
    use kuro_core::types::cell::SgrFlags;
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[2m");
    assert!(
        t.current_attrs().flags.contains(SgrFlags::DIM),
        "dim must be set by SGR 2"
    );
    t.advance(b"\x1b[22m");
    assert!(
        !t.current_attrs().flags.contains(SgrFlags::DIM),
        "dim must be cleared by SGR 22"
    );
}

// SGR 0 clears underline color as well as style.
#[test]
fn sgr_0_clears_underline_color() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[58:2:10:20:30m");
    t.advance(b"\x1b[0m");
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::Color::Default,
        "SGR 0 must reset underline_color to Default"
    );
    assert_eq!(
        t.current_attrs().underline_style,
        kuro_core::UnderlineStyle::None,
        "SGR 0 must reset underline_style to None"
    );
}

// SGR 58:2:R:G:B followed by SGR 4 (underline on) — both attributes active.
#[test]
fn sgr_underline_color_and_underline_both_active() {
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[4m");
    t.advance(b"\x1b[58:2:255:165:0m"); // orange underline color
    assert!(t.current_underline(), "underline must still be set");
    assert_eq!(
        t.current_attrs().underline_color,
        kuro_core::Color::Rgb(255, 165, 0),
        "underline color must be orange"
    );
}

// SGR 1;3;9 (bold+italic+strikethrough) followed by SGR 22;23;29 clears each.
#[test]
fn sgr_individual_clear_codes_for_bold_italic_strikethrough() {
    use kuro_core::types::cell::SgrFlags;
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[1;3;9m");
    assert!(t.current_bold(), "precondition: bold must be set");
    assert!(t.current_italic(), "precondition: italic must be set");
    assert!(
        t.current_attrs().flags.contains(SgrFlags::STRIKETHROUGH),
        "precondition: strikethrough must be set"
    );
    // SGR 22 = normal intensity (clears bold/dim), 23 = not italic, 29 = not strikethrough
    t.advance(b"\x1b[22;23;29m");
    assert!(!t.current_bold(), "SGR 22 must clear bold");
    assert!(!t.current_italic(), "SGR 23 must clear italic");
    assert!(
        !t.current_attrs().flags.contains(SgrFlags::STRIKETHROUGH),
        "SGR 29 must clear strikethrough"
    );
}

// SGR inverse (7) set and cleared by SGR 27.
#[test]
fn sgr_7_inverse_cleared_by_sgr_27() {
    use kuro_core::types::cell::SgrFlags;
    let mut t = TerminalCore::new(24, 80);
    t.advance(b"\x1b[7m");
    assert!(
        t.current_attrs().flags.contains(SgrFlags::INVERSE),
        "SGR 7 must set INVERSE"
    );
    t.advance(b"\x1b[27m");
    assert!(
        !t.current_attrs().flags.contains(SgrFlags::INVERSE),
        "SGR 27 must clear INVERSE"
    );
}
