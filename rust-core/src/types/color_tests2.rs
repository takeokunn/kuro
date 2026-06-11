    #[test]
    // SPOT-CHECK: Verify specific known RGB values for a sample of named colors.
    fn test_named_color_rgb_spot_checks() {
        assert_eq!(NamedColor::Black.to_rgb(), (0, 0, 0));
        assert_eq!(NamedColor::BrightRed.to_rgb(), (255, 0, 0));
        assert_eq!(NamedColor::BrightGreen.to_rgb(), (0, 255, 0));
        assert_eq!(NamedColor::BrightBlue.to_rgb(), (0, 0, 255));
        assert_eq!(NamedColor::BrightWhite.to_rgb(), (255, 255, 255));
    }

    #[test]
    // SPOT-CHECK: Grayscale boundary values.
    fn test_grayscale_boundary_values() {
        assert_eq!(Color::Indexed(232).to_rgb(), (8, 8, 8));
        assert_eq!(Color::Indexed(255).to_rgb(), (238, 238, 238));
    }

    #[test]
    // INVARIANT: Base named colors (Black..White) must have indices 0-7;
    // bright variants (BrightBlack..BrightWhite) must have indices 8-15.
    fn test_named_color_order() {
        assert_eq!(NamedColor::Black as u8, 0);
        assert_eq!(NamedColor::Red as u8, 1);
        assert_eq!(NamedColor::Green as u8, 2);
        assert_eq!(NamedColor::Yellow as u8, 3);
        assert_eq!(NamedColor::Blue as u8, 4);
        assert_eq!(NamedColor::Magenta as u8, 5);
        assert_eq!(NamedColor::Cyan as u8, 6);
        assert_eq!(NamedColor::White as u8, 7);
        assert_eq!(NamedColor::BrightBlack as u8, 8);
        assert_eq!(NamedColor::BrightRed as u8, 9);
        assert_eq!(NamedColor::BrightGreen as u8, 10);
        assert_eq!(NamedColor::BrightYellow as u8, 11);
        assert_eq!(NamedColor::BrightBlue as u8, 12);
        assert_eq!(NamedColor::BrightMagenta as u8, 13);
        assert_eq!(NamedColor::BrightCyan as u8, 14);
        assert_eq!(NamedColor::BrightWhite as u8, 15);
    }

    #[test]
    // EQUALITY: Color::Rgb(r,g,b) derives PartialEq.
    fn test_rgb_color_equality() {
        assert_eq!(Color::Rgb(10, 20, 30), Color::Rgb(10, 20, 30));
        assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(10, 20, 31));
        assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(10, 21, 30));
        assert_ne!(Color::Rgb(10, 20, 30), Color::Rgb(11, 20, 30));
    }

    #[test]
    // EQUALITY: Color::Indexed(n) derives PartialEq.
    fn test_color_indexed_equality() {
        assert_eq!(Color::Indexed(42), Color::Indexed(42));
        assert_ne!(Color::Indexed(42), Color::Indexed(43));
        assert_ne!(Color::Indexed(0), Color::Indexed(255));
    }

    #[test]
    // DISTINCTNESS: Color::Default, Color::Rgb, and Color::Indexed are distinct
    // enum variants.
    fn test_color_variants_not_equal_to_each_other() {
        assert_ne!(Color::Default, Color::Rgb(255, 255, 255));
        assert_ne!(Color::Default, Color::Indexed(0));
        assert_ne!(Color::Rgb(0, 0, 0), Color::Indexed(0));
        assert_ne!(Color::Rgb(203, 204, 205), Color::Indexed(7));
    }

    #[test]
    // FORMULA: The 6x6x6 cube red ramp.
    fn test_cube_red_ramp() {
        let cases: &[(u8, u8)] = &[
            (16, 0),
            (52, 51),
            (88, 102),
            (124, 153),
            (160, 204),
            (196, 255),
        ];
        for &(idx, expected_r) in cases {
            let (r, g, b) = Color::Indexed(idx).to_rgb();
            assert_eq!(r, expected_r, "idx={idx}: expected r={expected_r}");
            assert_eq!(g, 0, "idx={idx}: expected g=0");
            assert_eq!(b, 0, "idx={idx}: expected b=0");
        }
    }

    #[test]
    // FORMULA: The 6x6x6 cube green ramp.
    fn test_cube_green_ramp() {
        let cases: &[(u8, u8)] = &[
            (16, 0),
            (22, 51),
            (28, 102),
            (34, 153),
            (40, 204),
            (46, 255),
        ];
        for &(idx, expected_g) in cases {
            let (r, g, b) = Color::Indexed(idx).to_rgb();
            assert_eq!(r, 0, "idx={idx}: expected r=0");
            assert_eq!(g, expected_g, "idx={idx}: expected g={expected_g}");
            assert_eq!(b, 0, "idx={idx}: expected b=0");
        }
    }

    #[test]
    // INVARIANT: NamedColor::Black is standard terminal color 0.
    fn test_named_black_is_idx_0() {
        assert_eq!(NamedColor::Black as u8, 0);
        assert_eq!(NamedColor::Black.to_rgb(), (0, 0, 0));
        assert_eq!(Color::Indexed(0).to_rgb(), (0, 0, 0));
    }

    // PBT merged from tests/unit/types/color.rs
    proptest! {
        #![proptest_config(ProptestConfig::with_cases(1000))]

        #[test]
        // ROUNDTRIP: Color::Rgb(r,g,b).to_rgb() must return exactly (r,g,b)
        fn prop_rgb_identity(r in 0u8..=255u8, g in 0u8..=255u8, b in 0u8..=255u8) {
            prop_assert_eq!(Color::Rgb(r, g, b).to_rgb(), (r, g, b));
        }

        #[test]
        // INVARIANT: Color::Indexed(idx).to_rgb() never panics for any idx.
        fn prop_rgb_values_in_range(idx in 0u8..=255u8) {
            let color = Color::Indexed(idx);
            let _ = color.to_rgb();
        }

        #[test]
        // FORMULA: For indices 16-231 the colour cube formula must hold.
        fn prop_cube_formula(idx in 16u8..=231u8) {
            let (r, g, b) = Color::Indexed(idx).to_rgb();
            let n = idx - 16;
            let expected_r = (n / 36) * 51;
            let expected_g = ((n / 6) % 6) * 51;
            let expected_b = (n % 6) * 51;
            prop_assert_eq!(r, expected_r, "red component mismatch for idx={}", idx);
            prop_assert_eq!(g, expected_g, "green component mismatch for idx={}", idx);
            prop_assert_eq!(b, expected_b, "blue component mismatch for idx={}", idx);
        }
    }

    proptest! {
        #![proptest_config(ProptestConfig::with_cases(256))]

        #[test]
        // INVARIANT: NamedColor as u8 must be consistent and in 0..=15.
        fn prop_named_to_indexed_consistent(idx in 0u8..=15u8) {
            let all_named = [
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
            let named = all_named[idx as usize];
            let raw = named as u8;
            prop_assert_eq!(raw, idx, "NamedColor at slot {} must cast to {}", idx, idx);
            prop_assert!(raw <= 15, "NamedColor index must be <= 15, got {}", raw);
        }

        #[test]
        // PANIC SAFETY: Color::Indexed(n).to_rgb() for indices 0-15 must never panic.
        fn prop_all_system_color_indices_have_rgb(idx in 0u8..=15u8) {
            let _ = Color::Indexed(idx).to_rgb();
        }
    }
