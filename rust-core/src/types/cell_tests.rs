#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;

    #[test]
    fn test_cell_default() {
        let cell = Cell::default();
        assert_eq!(cell.grapheme.as_str(), " ");
        assert_eq!(cell.attrs.foreground, Color::Default);
    }

    #[test]
    fn test_cell_new() {
        let cell = Cell::new('A');
        assert_eq!(cell.grapheme.as_str(), "A");
        assert!(!cell.attrs.flags.contains(SgrFlags::BOLD));
    }

    #[test]
    fn test_cell_with_attrs() {
        let attrs = SgrAttributes {
            flags: SgrFlags::BOLD,
            foreground: Color::Rgb(255, 0, 0),
            ..Default::default()
        };

        let cell = Cell::with_attrs('B', attrs);
        assert_eq!(cell.grapheme.as_str(), "B");
        assert!(cell.attrs.flags.contains(SgrFlags::BOLD));
        assert_eq!(cell.attrs.foreground, Color::Rgb(255, 0, 0));
    }

    #[test]
    fn test_sgr_reset() {
        let mut attrs = SgrAttributes {
            flags: SgrFlags::BOLD | SgrFlags::ITALIC,
            ..Default::default()
        };

        attrs.reset();
        assert!(!attrs.flags.contains(SgrFlags::BOLD));
        assert!(!attrs.flags.contains(SgrFlags::ITALIC));
        assert_eq!(attrs.foreground, Color::Default);
    }

    #[test]
    fn test_cell_image_id_defaults_to_none() {
        let cell_default = Cell::default();
        assert_eq!(cell_default.image_id(), None);

        let cell_new = Cell::new('X');
        assert_eq!(cell_new.image_id(), None);
    }

    #[test]
    fn test_cell_equality() {
        let cell1 = Cell::new('A');
        let cell2 = Cell::new('A');
        assert_eq!(cell1, cell2);

        let attrs = SgrAttributes {
            flags: SgrFlags::BOLD,
            ..Default::default()
        };
        let cell3 = Cell::with_attrs('A', attrs);
        assert_ne!(cell1, cell3);
    }

    #[test]
    fn test_cell_with_hyperlink() {
        // A freshly created cell has no hyperlink
        let cell = Cell::new('A');
        assert_eq!(cell.hyperlink_id(), None);

        // with_hyperlink sets the hyperlink_id to the given String
        let linked_cell = cell.with_hyperlink(Arc::from("https://example.com"));
        assert_eq!(linked_cell.hyperlink_id(), Some("https://example.com"));

        // Replacing an existing hyperlink with a different one works correctly
        let relinked = linked_cell.with_hyperlink(Arc::from("https://other.com"));
        assert_eq!(relinked.hyperlink_id(), Some("https://other.com"));

        // Other fields are preserved after setting a hyperlink
        assert_eq!(relinked.char(), 'A');
        assert_eq!(relinked.width, CellWidth::Half);
        assert!(!relinked.attrs.flags.contains(SgrFlags::BOLD));
    }

    #[test]
    fn test_underline_style_default_is_none() {
        let attrs = SgrAttributes::default();
        assert_eq!(attrs.underline_style, UnderlineStyle::None);
        assert!(!attrs.underline());
    }

    #[test]
    fn test_underline_helper_method() {
        let mut attrs = SgrAttributes::default();
        assert!(!attrs.underline());
        attrs.underline_style = UnderlineStyle::Straight;
        assert!(attrs.underline());
        attrs.underline_style = UnderlineStyle::Curly;
        assert!(attrs.underline());
        attrs.underline_style = UnderlineStyle::None;
        assert!(!attrs.underline());
    }

    #[test]
    fn test_underline_color_default() {
        let attrs = SgrAttributes::default();
        assert_eq!(attrs.underline_color, Color::Default);
    }

    #[test]
    fn test_cell_default_is_space_with_half_width() {
        let cell = Cell::default();
        assert_eq!(cell.char(), ' ');
        assert_eq!(cell.width, CellWidth::Half);
        assert!(cell.extras.is_none());
        assert_eq!(cell.attrs, SgrAttributes::default());
    }

    #[test]
    fn test_cell_new_ascii_stores_char_and_no_extras() {
        let cell = Cell::new('Z');
        assert_eq!(cell.char(), 'Z');
        assert_eq!(cell.grapheme.as_str(), "Z");
        assert!(cell.extras.is_none());
    }

    #[test]
    fn test_cell_new_cjk_wide_char() {
        // '中' is a wide CJK character; Cell::new does NOT auto-detect width,
        // but with_char_and_width can be used.  Test that the char is stored.
        let cell = Cell::with_char_and_width('中', SgrAttributes::default(), CellWidth::Full);
        assert_eq!(cell.char(), '中');
        assert_eq!(cell.width, CellWidth::Full);
    }

    #[test]
    fn test_cell_char_getter_roundtrip() {
        for ch in ['a', 'Z', '!', '\u{1F600}'] {
            let cell = Cell::new(ch);
            assert_eq!(cell.char(), ch);
        }
    }

    #[test]
    fn test_set_hyperlink_id_some_stores_id() {
        let mut cell = Cell::new('A');
        cell.set_hyperlink_id(Some(Arc::from("https://example.com")));
        assert_eq!(cell.hyperlink_id(), Some("https://example.com"));
    }

    #[test]
    fn test_set_hyperlink_id_none_clears_but_keeps_image() {
        let mut cell = Cell::new('A');
        // Set both ids
        cell.set_hyperlink_id(Some(Arc::from("link")));
        cell.set_image_id(Some(42));
        // Clear hyperlink — image should survive
        cell.set_hyperlink_id(None);
        assert_eq!(cell.hyperlink_id(), None);
        assert_eq!(cell.image_id(), Some(42));
    }

    #[test]
    fn test_set_image_id_some_stores_id() {
        let mut cell = Cell::new('A');
        cell.set_image_id(Some(99));
        assert_eq!(cell.image_id(), Some(99));
    }

    #[test]
    fn test_set_image_id_none_clears_but_keeps_hyperlink() {
        let mut cell = Cell::new('A');
        cell.set_hyperlink_id(Some(Arc::from("link")));
        cell.set_image_id(Some(7));
        // Clear image — hyperlink should survive
        cell.set_image_id(None);
        assert_eq!(cell.image_id(), None);
        assert_eq!(cell.hyperlink_id(), Some("link"));
    }

    #[test]
    fn test_cell_extras_none_when_no_ids() {
        let cell = Cell::new('A');
        // Neither hyperlink nor image set → extras must be None
        assert!(cell.extras.is_none());
        assert_eq!(cell.hyperlink_id(), None);
        assert_eq!(cell.image_id(), None);
    }

    #[test]
    fn test_sgr_reset_clears_all_fields() {
        let mut attrs = SgrAttributes {
            foreground: Color::Rgb(1, 2, 3),
            background: Color::Indexed(5),
            flags: SgrFlags::BOLD | SgrFlags::ITALIC | SgrFlags::STRIKETHROUGH,
            underline_style: UnderlineStyle::Curly,
            underline_color: Color::Rgb(0, 0, 0),
            overline: true,
            superscript: true,
            subscript: false,
        };
        attrs.reset();
        assert_eq!(attrs, SgrAttributes::default());
        assert!(attrs.flags.is_empty());
        assert_eq!(attrs.foreground, Color::Default);
        assert_eq!(attrs.background, Color::Default);
        assert_eq!(attrs.underline_style, UnderlineStyle::None);
        assert_eq!(attrs.underline_color, Color::Default);
    }

    // SGR attribute tests (logically belong to SgrAttributes in cell.rs)

    #[test]
    fn test_sgr_attributes_default_has_no_flags() {
        let attrs = SgrAttributes::default();
        assert!(attrs.flags.is_empty());
        assert_eq!(attrs.foreground, Color::Default);
        assert_eq!(attrs.background, Color::Default);
    }

    #[test]
    fn test_sgr_attributes_bold_flag() {
        let attrs = SgrAttributes {
            flags: SgrFlags::BOLD,
            ..Default::default()
        };
        assert!(attrs.flags.contains(SgrFlags::BOLD));
        assert!(!attrs.flags.contains(SgrFlags::ITALIC));
    }

    #[test]
    fn test_sgr_attributes_bold_and_italic() {
        let attrs = SgrAttributes {
            flags: SgrFlags::BOLD | SgrFlags::ITALIC,
            ..Default::default()
        };
        assert!(attrs.flags.contains(SgrFlags::BOLD));
        assert!(attrs.flags.contains(SgrFlags::ITALIC));
    }

    #[test]
    fn test_sgr_attributes_256_color_fg() {
        let attrs = SgrAttributes {
            foreground: Color::Indexed(200),
            ..Default::default()
        };
        assert_eq!(attrs.foreground, Color::Indexed(200));
    }

    #[test]
    fn test_sgr_attributes_rgb_fg_stores_components() {
        let attrs = SgrAttributes {
            foreground: Color::Rgb(10, 20, 30),
            ..Default::default()
        };
        assert_eq!(attrs.foreground, Color::Rgb(10, 20, 30));
        if let Color::Rgb(r, g, b) = attrs.foreground {
            assert_eq!(r, 10);
            assert_eq!(g, 20);
            assert_eq!(b, 30);
        } else {
            panic!("expected Color::Rgb");
        }
    }

    #[test]
    fn test_underline_style_default_is_none_variant() {
        let attrs = SgrAttributes::default();
        assert_eq!(attrs.underline_style, UnderlineStyle::None);
    }

    #[test]
    fn test_is_all_default_true_for_fresh_attrs() {
        let attrs = SgrAttributes::default();
        assert!(
            attrs.is_all_default(),
            "SgrAttributes::default() must satisfy is_all_default"
        );
    }

    #[test]
    fn test_is_all_default_false_when_flags_set() {
        let mut attrs = SgrAttributes::default();
        attrs.flags = SgrFlags::BOLD;
        assert!(!attrs.is_all_default(), "BOLD flag must make is_all_default false");
    }

    #[test]
    fn test_is_all_default_false_when_overline_set() {
        let mut attrs = SgrAttributes::default();
        attrs.overline = true;
        assert!(!attrs.is_all_default(), "overline must make is_all_default false");
    }

    #[test]
    fn test_is_all_default_false_when_foreground_set() {
        let mut attrs = SgrAttributes::default();
        attrs.foreground = Color::Named(crate::types::NamedColor::Red);
        assert!(!attrs.is_all_default(), "non-default foreground must make is_all_default false");
    }

    #[test]
    fn test_is_all_default_false_when_background_set() {
        let mut attrs = SgrAttributes::default();
        attrs.background = Color::Indexed(100);
        assert!(!attrs.is_all_default(), "non-default background must make is_all_default false");
    }

    #[test]
    fn test_is_all_default_false_when_underline_color_set() {
        let mut attrs = SgrAttributes::default();
        attrs.underline_color = Color::Rgb(10, 20, 30);
        assert!(!attrs.is_all_default(), "non-default underline_color must make is_all_default false");
    }

    #[test]
    fn test_is_all_default_false_when_underline_style_set() {
        let mut attrs = SgrAttributes::default();
        attrs.underline_style = UnderlineStyle::Curly;
        assert!(!attrs.is_all_default(), "Curly underline style must make is_all_default false");
    }

    #[test]
    fn test_sgr_attributes_equality() {
        let a = SgrAttributes {
            flags: SgrFlags::BOLD,
            foreground: Color::Rgb(1, 2, 3),
            ..Default::default()
        };
        let b = SgrAttributes {
            flags: SgrFlags::BOLD,
            foreground: Color::Rgb(1, 2, 3),
            ..Default::default()
        };
        assert_eq!(a, b);
        let c = SgrAttributes {
            flags: SgrFlags::DIM,
            ..Default::default()
        };
        assert_ne!(a, c);
    }

    // ── SgrFlags primitive methods ──────────────────────────────────────────────

    #[test]
    fn test_sgr_flags_bits_roundtrip() {
        // bits() must return the raw u8 stored inside SgrFlags.
        let flags = SgrFlags::BOLD | SgrFlags::ITALIC;
        let raw = flags.bits();
        assert_eq!(SgrFlags::from_bits_truncate(raw), flags,
            "from_bits_truncate(bits()) must produce the original value");
    }

    #[test]
    fn test_sgr_flags_insert_adds_bits() {
        let mut flags = SgrFlags::BOLD;
        flags.insert(SgrFlags::ITALIC);
        assert!(flags.contains(SgrFlags::BOLD),  "BOLD must remain set after insert(ITALIC)");
        assert!(flags.contains(SgrFlags::ITALIC), "ITALIC must be set after insert(ITALIC)");
    }

    #[test]
    fn test_sgr_flags_remove_clears_bits() {
        let mut flags = SgrFlags::BOLD | SgrFlags::ITALIC;
        flags.remove(SgrFlags::BOLD);
        assert!(!flags.contains(SgrFlags::BOLD), "BOLD must be clear after remove(BOLD)");
        assert!(flags.contains(SgrFlags::ITALIC), "ITALIC must remain after remove(BOLD)");
    }

    #[test]
    fn test_sgr_flags_set_true_inserts() {
        let mut flags = SgrFlags::default();
        flags.set(SgrFlags::DIM, true);
        assert!(flags.contains(SgrFlags::DIM), "set(DIM, true) must add the DIM bit");
    }

    #[test]
    fn test_sgr_flags_set_false_removes() {
        let mut flags = SgrFlags::DIM | SgrFlags::BOLD;
        flags.set(SgrFlags::DIM, false);
        assert!(!flags.contains(SgrFlags::DIM), "set(DIM, false) must clear the DIM bit");
        assert!(flags.contains(SgrFlags::BOLD),  "BOLD must be unaffected by set(DIM, false)");
    }

    #[test]
    fn test_sgr_flags_from_bits_truncate_preserves_all_bits() {
        // All 8 bits must survive a round-trip through from_bits_truncate.
        let raw: u8 = 0b1111_1111;
        let flags = SgrFlags::from_bits_truncate(raw);
        assert_eq!(flags.bits(), raw, "all 8 bits must be preserved");
    }

    include!("cell_pbt.rs");
}
