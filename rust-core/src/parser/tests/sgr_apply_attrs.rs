// Direct unit tests for `apply_sgr_attrs`.
//
// `apply_sgr_attrs` is the attribute-only mirror of `handle_sgr`: it applies
// SGR parameter groups directly to an `SgrAttributes` value without requiring
// a `TerminalCore` or VTE parser.  DECCARA uses it to re-apply SGR semantics
// to existing cells.  Passing `u16` slices directly is cheaper and more
// precise than encoding escape sequences through the full VTE pipeline.

use crate::parser::sgr::apply_sgr_attrs;
use crate::types::{
    cell::{SgrAttributes, UnderlineStyle},
    Color,
};

fn fresh_attrs() -> SgrAttributes {
    SgrAttributes::default()
}

#[test]
fn apply_sgr_attrs_empty_groups_resets_to_default() {
    let mut a = fresh_attrs();
    a.flags.insert(SgrFlags::BOLD);
    apply_sgr_attrs(&mut a, &[]);
    assert!(!a.flags.contains(SgrFlags::BOLD), "empty groups must reset");
}

#[test]
fn apply_sgr_attrs_bold_sets_flag() {
    let mut a = fresh_attrs();
    let bold: &[u16] = &[1];
    apply_sgr_attrs(&mut a, &[bold]);
    assert!(a.flags.contains(SgrFlags::BOLD));
}

#[test]
fn apply_sgr_attrs_sgr0_resets_bold() {
    let mut a = fresh_attrs();
    a.flags.insert(SgrFlags::BOLD);
    let reset: &[u16] = &[0];
    apply_sgr_attrs(&mut a, &[reset]);
    assert!(!a.flags.contains(SgrFlags::BOLD));
}

#[test]
fn apply_sgr_attrs_italic_on_and_off() {
    let mut a = fresh_attrs();
    let on:  &[u16] = &[3];
    let off: &[u16] = &[23];
    apply_sgr_attrs(&mut a, &[on]);
    assert!(a.flags.contains(SgrFlags::ITALIC));
    apply_sgr_attrs(&mut a, &[off]);
    assert!(!a.flags.contains(SgrFlags::ITALIC));
}

#[test]
fn apply_sgr_attrs_underline_style_straight() {
    let mut a = fresh_attrs();
    let ul: &[u16] = &[4];
    apply_sgr_attrs(&mut a, &[ul]);
    assert_eq!(a.underline_style, UnderlineStyle::Straight);
}

#[test]
fn apply_sgr_attrs_underline_subparam_curly() {
    let mut a = fresh_attrs();
    let curly: &[u16] = &[4, 3];
    apply_sgr_attrs(&mut a, &[curly]);
    assert_eq!(a.underline_style, UnderlineStyle::Curly);
}

#[test]
fn apply_sgr_attrs_underline_subparam_0_clears() {
    let mut a = fresh_attrs();
    let on:  &[u16] = &[4];
    let off: &[u16] = &[4, 0];
    apply_sgr_attrs(&mut a, &[on]);
    apply_sgr_attrs(&mut a, &[off]);
    assert_eq!(a.underline_style, UnderlineStyle::None);
}

#[test]
fn apply_sgr_attrs_foreground_named_red() {
    let mut a = fresh_attrs();
    let red: &[u16] = &[31];
    apply_sgr_attrs(&mut a, &[red]);
    assert!(matches!(a.foreground, Color::Named(_)));
    assert_ne!(a.foreground, Color::Default);
}

#[test]
fn apply_sgr_attrs_foreground_default_resets() {
    let mut a = fresh_attrs();
    let red:  &[u16] = &[31];
    let dflt: &[u16] = &[39];
    apply_sgr_attrs(&mut a, &[red, dflt]);
    assert_eq!(a.foreground, Color::Default);
}

#[test]
fn apply_sgr_attrs_overline_on_off() {
    let mut a = fresh_attrs();
    let on:  &[u16] = &[53];
    let off: &[u16] = &[55];
    apply_sgr_attrs(&mut a, &[on]);
    assert!(a.overline);
    apply_sgr_attrs(&mut a, &[off]);
    assert!(!a.overline);
}

#[test]
fn apply_sgr_attrs_superscript_subscript_exclusive() {
    let mut a = fresh_attrs();
    let sup: &[u16] = &[73];
    let sub: &[u16] = &[75];
    let off: &[u16] = &[74];
    apply_sgr_attrs(&mut a, &[sup]);
    assert!(a.superscript && !a.subscript);
    apply_sgr_attrs(&mut a, &[sub]);
    assert!(a.subscript && !a.superscript);
    apply_sgr_attrs(&mut a, &[off]);
    assert!(!a.superscript && !a.subscript);
}

#[test]
fn apply_sgr_attrs_skip_empty_group() {
    let mut a = fresh_attrs();
    let empty: &[u16] = &[];
    let bold:  &[u16] = &[1];
    apply_sgr_attrs(&mut a, &[empty, bold]);
    assert!(a.flags.contains(SgrFlags::BOLD), "empty group must be skipped");
}

#[test]
fn apply_sgr_attrs_dim_on() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[2u16]]);
    assert!(a.flags.contains(SgrFlags::DIM));
}

#[test]
fn apply_sgr_attrs_dim_off_via_sgr22() {
    let mut a = fresh_attrs();
    a.flags.insert(SgrFlags::BOLD);
    a.flags.insert(SgrFlags::DIM);
    apply_sgr_attrs(&mut a, &[&[22u16]]);
    assert!(!a.flags.contains(SgrFlags::BOLD));
    assert!(!a.flags.contains(SgrFlags::DIM));
}

#[test]
fn apply_sgr_attrs_blink_slow_on() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[5u16]]);
    assert!(a.flags.contains(SgrFlags::BLINK_SLOW));
}

#[test]
fn apply_sgr_attrs_blink_fast_on() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[6u16]]);
    assert!(a.flags.contains(SgrFlags::BLINK_FAST));
}

#[test]
fn apply_sgr_attrs_blink_off_via_sgr25() {
    let mut a = fresh_attrs();
    a.flags.insert(SgrFlags::BLINK_SLOW);
    a.flags.insert(SgrFlags::BLINK_FAST);
    apply_sgr_attrs(&mut a, &[&[25u16]]);
    assert!(!a.flags.contains(SgrFlags::BLINK_SLOW));
    assert!(!a.flags.contains(SgrFlags::BLINK_FAST));
}

#[test]
fn apply_sgr_attrs_inverse_on_off() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[7u16]]);
    assert!(a.flags.contains(SgrFlags::INVERSE));
    apply_sgr_attrs(&mut a, &[&[27u16]]);
    assert!(!a.flags.contains(SgrFlags::INVERSE));
}

#[test]
fn apply_sgr_attrs_hidden_on_off() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[8u16]]);
    assert!(a.flags.contains(SgrFlags::HIDDEN));
    apply_sgr_attrs(&mut a, &[&[28u16]]);
    assert!(!a.flags.contains(SgrFlags::HIDDEN));
}

#[test]
fn apply_sgr_attrs_strikethrough_on_off() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[9u16]]);
    assert!(a.flags.contains(SgrFlags::STRIKETHROUGH));
    apply_sgr_attrs(&mut a, &[&[29u16]]);
    assert!(!a.flags.contains(SgrFlags::STRIKETHROUGH));
}

#[test]
fn apply_sgr_attrs_double_underline_direct_sgr21() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[21u16]]);
    assert_eq!(a.underline_style, UnderlineStyle::Double);
}

#[test]
fn apply_sgr_attrs_background_named_green() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[42u16]]);
    assert!(matches!(a.background, Color::Named(_)));
    assert_ne!(a.background, Color::Default);
}

#[test]
fn apply_sgr_attrs_background_default_resets() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[42u16]]);
    apply_sgr_attrs(&mut a, &[&[49u16]]);
    assert_eq!(a.background, Color::Default);
}

#[test]
fn apply_sgr_attrs_underline_color_direct_rgb() {
    let mut a = fresh_attrs();
    // SGR 58:2:255:0:128 — direct RGB underline color
    let uc: &[u16] = &[58, 2, 255, 0, 128];
    apply_sgr_attrs(&mut a, &[uc]);
    assert!(matches!(a.underline_color, Color::Rgb(..)));
}

#[test]
fn apply_sgr_attrs_underline_color_default_resets() {
    let mut a = fresh_attrs();
    let uc: &[u16] = &[58, 2, 255, 0, 128];
    apply_sgr_attrs(&mut a, &[uc]);
    apply_sgr_attrs(&mut a, &[&[59u16]]);
    assert_eq!(a.underline_color, Color::Default);
}

#[test]
fn apply_sgr_attrs_bright_foreground_90_to_97() {
    let mut a = fresh_attrs();
    for param in 90u16..=97 {
        apply_sgr_attrs(&mut a, &[&[param]]);
        assert!(matches!(a.foreground, Color::Named(_)), "SGR {param} must set bright fg");
    }
}

#[test]
fn apply_sgr_attrs_bright_background_100_to_107() {
    let mut a = fresh_attrs();
    for param in 100u16..=107 {
        apply_sgr_attrs(&mut a, &[&[param]]);
        assert!(matches!(a.background, Color::Named(_)), "SGR {param} must set bright bg");
    }
}

#[test]
fn apply_sgr_attrs_unknown_param_is_ignored() {
    let mut a = fresh_attrs();
    let before = format!("{a:?}");
    apply_sgr_attrs(&mut a, &[&[999u16]]);
    let after = format!("{a:?}");
    assert_eq!(before, after, "unknown SGR param must not change attrs");
}

#[test]
fn apply_sgr_attrs_underline_subparam_dotted() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[4u16, 4]]);
    assert_eq!(a.underline_style, UnderlineStyle::Dotted);
}

#[test]
fn apply_sgr_attrs_underline_subparam_dashed() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[4u16, 5]]);
    assert_eq!(a.underline_style, UnderlineStyle::Dashed);
}

#[test]
fn apply_sgr_attrs_underline_subparam_double() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[4u16, 2]]);
    assert_eq!(a.underline_style, UnderlineStyle::Double);
}

#[test]
fn apply_sgr_attrs_underline_subparam_unknown_defaults_to_straight() {
    let mut a = fresh_attrs();
    apply_sgr_attrs(&mut a, &[&[4u16, 99]]);
    assert_eq!(a.underline_style, UnderlineStyle::Straight);
}
