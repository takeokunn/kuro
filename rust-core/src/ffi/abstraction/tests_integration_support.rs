use crate::types::cell::{Cell, SgrAttributes, SgrFlags};
use crate::types::color::{Color, NamedColor};
use proptest::prelude::*;

pub(crate) fn arb_color() -> impl Strategy<Value = Color> {
    prop_oneof![
        Just(Color::Default),
        (0u8..=15u8).prop_map(|idx| {
            let named = match idx {
                0 => NamedColor::Black,
                1 => NamedColor::Red,
                2 => NamedColor::Green,
                3 => NamedColor::Yellow,
                4 => NamedColor::Blue,
                5 => NamedColor::Magenta,
                6 => NamedColor::Cyan,
                7 => NamedColor::White,
                8 => NamedColor::BrightBlack,
                9 => NamedColor::BrightRed,
                10 => NamedColor::BrightGreen,
                11 => NamedColor::BrightYellow,
                12 => NamedColor::BrightBlue,
                13 => NamedColor::BrightMagenta,
                14 => NamedColor::BrightCyan,
                _ => NamedColor::BrightWhite,
            };
            Color::Named(named)
        }),
        any::<u8>().prop_map(Color::Indexed),
        (any::<u8>(), any::<u8>(), any::<u8>()).prop_map(|(r, g, b)| Color::Rgb(r, g, b)),
    ]
}

pub(crate) fn arb_sgr_attrs() -> impl Strategy<Value = SgrAttributes> {
    (
        arb_color(),
        arb_color(),
        any::<bool>(),
        any::<bool>(),
        any::<bool>(),
        any::<bool>(),
        any::<bool>(),
        any::<bool>(),
        any::<bool>(),
        any::<bool>(),
        any::<bool>(),
    )
        .prop_map(
            |(
                fg,
                bg,
                bold,
                dim,
                italic,
                underline,
                blink_slow,
                blink_fast,
                inverse,
                hidden,
                strikethrough,
            )| {
                let mut flags = SgrFlags::default();
                flags.set(SgrFlags::BOLD, bold);
                flags.set(SgrFlags::DIM, dim);
                flags.set(SgrFlags::ITALIC, italic);
                flags.set(SgrFlags::BLINK_SLOW, blink_slow);
                flags.set(SgrFlags::BLINK_FAST, blink_fast);
                flags.set(SgrFlags::INVERSE, inverse);
                flags.set(SgrFlags::HIDDEN, hidden);
                flags.set(SgrFlags::STRIKETHROUGH, strikethrough);
                SgrAttributes {
                    foreground: fg,
                    background: bg,
                    flags,
                    underline_style: if underline {
                        crate::types::cell::UnderlineStyle::Straight
                    } else {
                        crate::types::cell::UnderlineStyle::None
                    },
                    underline_color: Color::Default,
                    overline: false,
                    superscript: false,
                    subscript: false,
                }
            },
        )
}

pub(crate) fn arb_cell() -> impl Strategy<Value = Cell> {
    (arb_sgr_attrs(), any::<char>()).prop_map(|(attrs, c)| Cell::with_attrs(c, attrs))
}
