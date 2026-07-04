// SGR 39 resets foreground; SGR 49 resets background — two flavours, one macro.
test_sgr_color_default_reset!(
    test_sgr_39_resets_foreground_macro,
    b"\x1b[32m",
    b"\x1b[39m",
    foreground,
    "foreground"
);
test_sgr_color_default_reset!(
    test_sgr_49_resets_background_macro,
    b"\x1b[42m",
    b"\x1b[49m",
    background,
    "background"
);

// Boundary values: index 0 (first entry) and 255 (last entry).
test_sgr_indexed_color_pair!(test_sgr_256_fg_index_0, test_sgr_256_bg_index_0, 0);
test_sgr_indexed_color_pair!(test_sgr_256_fg_index_255, test_sgr_256_bg_index_255, 255);

test_sgr_truecolor!(
    test_sgr_truecolor_black_fg,
    38,
    foreground,
    0,
    0,
    0,
    "SGR 38;2;0;0;0 must produce Rgb(0,0,0) even though it encodes like Default"
);
test_sgr_truecolor!(
    test_sgr_truecolor_white_fg,
    38,
    foreground,
    255,
    255,
    255,
    "SGR 38;2;255;255;255 must produce Rgb(255,255,255)"
);
test_sgr_truecolor!(
    test_sgr_truecolor_white_bg,
    48,
    background,
    255,
    255,
    255,
    "SGR 48;2;255;255;255 must produce Rgb(255,255,255) background"
);

test_sgr_unknown_noop!(
    test_sgr_unknown_200_is_noop,
    b"\x1b[1m\x1b[32m", // BOLD on + green fg
    b"\x1b[200m",
    BOLD,
    "SGR 200 must not clear BOLD",
    foreground,
    crate::types::Color::Named(crate::types::NamedColor::Green),
    "SGR 200 must not alter foreground color"
);
test_sgr_unknown_noop!(
    test_sgr_unknown_150_is_noop,
    b"\x1b[3m", // ITALIC on
    b"\x1b[150m",
    ITALIC,
    "SGR 150 must not clear ITALIC",
    background,
    crate::types::Color::Default,
    "SGR 150 must not set background"
);

test_sgr_all_named_colors!(test_sgr_all_normal_fg_colors_30_to_37, 30, foreground, "Fg");
test_sgr_all_named_colors!(test_sgr_all_normal_bg_colors_40_to_47, 40, background, "Bg");
