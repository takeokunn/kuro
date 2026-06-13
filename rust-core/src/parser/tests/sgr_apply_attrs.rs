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
