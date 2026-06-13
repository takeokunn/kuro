
/// Serialize `attrs` back into an SGR parameter string for DECRQSS (`DCS $ q m`).
///
/// Begins with `0` (reset) and appends a parameter for each active attribute,
/// matching the xterm convention (so the default rendition serializes to `0`).
/// Every emitted form round-trips through this module's own parser — semicolon
/// form for the 38/48/58 extended colors, `4:n` for styled underlines — so a
/// client that re-applies the reported string recreates the exact rendition.
pub(crate) fn serialize_sgr(attrs: &SgrAttributes) -> String {
    use std::fmt::Write as _;

    let mut out = String::from("0");
    let f = attrs.flags;
    if f.contains(SgrFlags::BOLD) {
        out.push_str(";1");
    }
    if f.contains(SgrFlags::DIM) {
        out.push_str(";2");
    }
    if f.contains(SgrFlags::ITALIC) {
        out.push_str(";3");
    }
    match attrs.underline_style {
        UnderlineStyle::None => {}
        UnderlineStyle::Straight => out.push_str(";4"),
        UnderlineStyle::Double => out.push_str(";4:2"),
        UnderlineStyle::Curly => out.push_str(";4:3"),
        UnderlineStyle::Dotted => out.push_str(";4:4"),
        UnderlineStyle::Dashed => out.push_str(";4:5"),
    }
    if f.contains(SgrFlags::BLINK_SLOW) {
        out.push_str(";5");
    }
    if f.contains(SgrFlags::BLINK_FAST) {
        out.push_str(";6");
    }
    if f.contains(SgrFlags::INVERSE) {
        out.push_str(";7");
    }
    if f.contains(SgrFlags::HIDDEN) {
        out.push_str(";8");
    }
    if f.contains(SgrFlags::STRIKETHROUGH) {
        out.push_str(";9");
    }
    if attrs.superscript {
        out.push_str(";73");
    }
    if attrs.subscript {
        out.push_str(";75");
    }
    if attrs.overline {
        out.push_str(";53");
    }
    append_sgr_color(&mut out, attrs.foreground, 30, 90, 38);
    append_sgr_color(&mut out, attrs.background, 40, 100, 48);
    // Underline color: only indexed (58;5;n) or RGB (58;2;r;g;b) — the parser
    // never produces a named underline color, so that variant is unreachable.
    match attrs.underline_color {
        Color::Indexed(n) => {
            let _ = write!(out, ";58;5;{n}");
        }
        Color::Rgb(r, g, b) => {
            let _ = write!(out, ";58;2;{r};{g};{b}");
        }
        Color::Default | Color::Named(_) => {}
    }
    out
}

/// Append one foreground/background color to an SGR string.
///
/// `base`/`bright_base` are the named-color SGR bases (30/90 for fg, 40/100 for
/// bg) and `ext` is the extended-color introducer (38 fg, 48 bg).
fn append_sgr_color(out: &mut String, color: Color, base: u8, bright_base: u8, ext: u8) {
    use std::fmt::Write as _;
    match color {
        Color::Default => {}
        Color::Named(n) => {
            let idx = n as u8;
            let code = if idx < 8 {
                base + idx
            } else {
                bright_base + (idx - 8)
            };
            let _ = write!(out, ";{code}");
        }
        Color::Indexed(i) => {
            let _ = write!(out, ";{ext};5;{i}");
        }
        Color::Rgb(r, g, b) => {
            let _ = write!(out, ";{ext};2;{r};{g};{b}");
        }
    }
}
