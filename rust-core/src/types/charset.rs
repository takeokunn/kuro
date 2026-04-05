//! Terminal character set designation types and DEC line drawing translation.

/// Terminal character set designation
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum CharsetType {
    /// US ASCII (default)
    #[default]
    Ascii,
    /// DEC Special Graphics (line drawing)
    DecLineDrawing,
}

/// DEC line drawing character translation table.
/// Maps ASCII 0x60-0x7E to Unicode box-drawing equivalents.
/// Index 0 = ASCII 0x60 ('`'), index 30 = ASCII 0x7E ('~')
pub const DEC_LINE_DRAWING_TABLE: [char; 31] = [
    '\u{25C6}', // 0x60 ` → ◆ diamond
    '\u{2592}', // 0x61 a → ▒ checkerboard
    '\u{2409}', // 0x62 b → ␉ HT symbol
    '\u{240C}', // 0x63 c → ␌ FF symbol
    '\u{240D}', // 0x64 d → ␍ CR symbol
    '\u{240A}', // 0x65 e → ␊ LF symbol
    '\u{00B0}', // 0x66 f → ° degree
    '\u{00B1}', // 0x67 g → ± plus/minus
    '\u{2424}', // 0x68 h → ␤ NL symbol
    '\u{240B}', // 0x69 i → ␋ VT symbol
    '\u{2518}', // 0x6A j → ┘ lower-right corner
    '\u{2510}', // 0x6B k → ┐ upper-right corner
    '\u{250C}', // 0x6C l → ┌ upper-left corner
    '\u{2514}', // 0x6D m → └ lower-left corner
    '\u{253C}', // 0x6E n → ┼ crossing lines
    '\u{23BA}', // 0x6F o → ⎺ scan line 1
    '\u{23BB}', // 0x70 p → ⎻ scan line 3
    '\u{2500}', // 0x71 q → ─ horizontal line
    '\u{23BC}', // 0x72 r → ⎼ scan line 7
    '\u{23BD}', // 0x73 s → ⎽ scan line 9
    '\u{251C}', // 0x74 t → ├ left tee
    '\u{2524}', // 0x75 u → ┤ right tee
    '\u{2534}', // 0x76 v → ┴ bottom tee
    '\u{252C}', // 0x77 w → ┬ top tee
    '\u{2502}', // 0x78 x → │ vertical line
    '\u{2264}', // 0x79 y → ≤ less-than-or-equal
    '\u{2265}', // 0x7A z → ≥ greater-than-or-equal
    '\u{03C0}', // 0x7B { → π pi
    '\u{2260}', // 0x7C | → ≠ not-equal
    '\u{00A3}', // 0x7D } → £ pound sterling
    '\u{00B7}', // 0x7E ~ → · centered dot / bullet
];

/// Translate a character through the DEC line drawing charset.
/// Only translates bytes in 0x60..=0x7E range; all others pass through.
#[inline]
pub fn translate_dec_line_drawing(c: char) -> char {
    let b = c as u32;
    if (0x60..=0x7E).contains(&b) {
        DEC_LINE_DRAWING_TABLE[(b - 0x60) as usize]
    } else {
        c
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_charset_is_ascii() {
        assert_eq!(CharsetType::default(), CharsetType::Ascii);
    }

    #[test]
    fn translate_all_31_entries() {
        for (i, &expected) in DEC_LINE_DRAWING_TABLE.iter().enumerate() {
            let ascii = char::from(0x60 + i as u8);
            assert_eq!(
                translate_dec_line_drawing(ascii),
                expected,
                "index {i} (0x{:02X})",
                0x60 + i
            );
        }
    }

    #[test]
    fn translate_outside_range_passes_through() {
        assert_eq!(translate_dec_line_drawing('A'), 'A');
        assert_eq!(translate_dec_line_drawing(' '), ' ');
        assert_eq!(translate_dec_line_drawing('0'), '0');
        // 0x5F is just below the range
        assert_eq!(translate_dec_line_drawing('\x5F'), '\x5F');
        // 0x7F is just above the range
        assert_eq!(translate_dec_line_drawing('\x7F'), '\x7F');
    }

    #[test]
    fn translate_key_box_drawing_chars() {
        assert_eq!(translate_dec_line_drawing('j'), '┘');
        assert_eq!(translate_dec_line_drawing('k'), '┐');
        assert_eq!(translate_dec_line_drawing('l'), '┌');
        assert_eq!(translate_dec_line_drawing('m'), '└');
        assert_eq!(translate_dec_line_drawing('q'), '─');
        assert_eq!(translate_dec_line_drawing('x'), '│');
    }
}
