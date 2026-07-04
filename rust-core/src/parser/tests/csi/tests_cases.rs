use super::*;

test_cursor_commands! {
    // VPA: CSI 5 d — row 5 (1-indexed) -> row 4 (0-indexed), col unchanged
    test_vpa_move_cursor:        b"\x1b[5d"     => (4,  0),
    // CHA: CSI 20 G — col 20 (1-indexed) -> col 19 (0-indexed), row unchanged
    test_cha_move_cursor:        b"\x1b[20G"    => (0, 19),
    // HVP: CSI 10;30 f — (row=10, col=30) 1-indexed -> (9, 29) 0-indexed
    test_hvp_move_cursor:        b"\x1b[10;30f" => (9, 29),
    // HVP partial: CSI 5 f — row=5, col defaults to 1 -> (4, 0)
    test_hvp_partial_params:     b"\x1b[5f"     => (4,  0),
    // CUP explicit params: CSI 5;10 H -> (4, 9) 0-indexed
    test_cup_multi_param_semicolon: b"\x1b[5;10H" => (4, 9),
    // CUD: CSI 4 B — move down 4 from row 0 -> row 4
    test_cud_move_cursor_down:   b"\x1b[4B"     => (4,  0),
    // CUF: CSI 10 C — move right 10 from col 0 -> col 10
    test_cuf_move_cursor_right:  b"\x1b[10C"    => (0, 10),
}

test_cursor_default! {
    // CUU default (no param) moves up 1
    test_cuu_default: csi_cuu, (4, 0)  => (3, 0),
    // CUD default (no param) moves down 1
    test_cud_default: csi_cud, (3, 0)  => (4, 0),
    // CUF default (no param) moves right 1
    test_cuf_default: csi_cuf, (0, 5)  => (0, 6),
    // CUB default (no param) moves left 1
    test_cub_default: csi_cub, (0, 10) => (0, 9),
}

test_cursor_sequence! {
    // VPA: CSI d defaults to row 1 and clamps at bottom.
    test_vpa_default: start (9, 0), b"\x1b[d" => (0, 0),
    test_vpa_bounds: start (0, 0), b"\x1b[100d" => (23, 0),
    // CHA: CSI G defaults to column 1 and clamps at right edge.
    test_cha_default: start (0, 29), b"\x1b[G" => (0, 0),
    test_cha_bounds: start (0, 0), b"\x1b[100G" => (0, 79),
    // HVP: CSI f defaults to (1, 1) and clamps to screen bounds.
    test_hvp_default: start (14, 39), b"\x1b[f" => (0, 0),
    test_hvp_bounds: start (0, 0), b"\x1b[100;100f" => (23, 79),
    // CUU / CUD / CUF / CUB.
    test_cuu_move_cursor_up: start (5, 0), b"\x1b[3A" => (2, 0),
    test_cuu_clamps_at_top: start (0, 0), b"\x1b[5A" => (0, 0),
    test_cud_clamps_at_bottom: start (23, 0), b"\x1b[5B" => (23, 0),
    test_cuf_clamps_at_right_margin: start (0, 79), b"\x1b[5C" => (0, 79),
    test_cub_move_cursor_left: start (0, 15), b"\x1b[7D" => (0, 8),
    test_cub_clamps_at_left_margin: start (0, 0), b"\x1b[5D" => (0, 0),
    // CUP.
    test_cup_absolute_position: start (0, 0), b"\x1b[8;25H" => (7, 24),
    test_cup_default: start (10, 30), b"\x1b[H" => (0, 0),
    test_cup_bounds: start (0, 0), b"\x1b[100;100H" => (23, 79),
    // CNL / CPL.
    test_cnl_moves_down_and_to_col0: start (3, 15), b"\x1b[2E" => (5, 0),
    test_cnl_default_is_1: start (5, 20), b"\x1b[E" => (6, 0),
    test_cpl_moves_up_and_to_col0: start (10, 40), b"\x1b[3F" => (7, 0),
    test_cpl_default_is_1: start (5, 20), b"\x1b[F" => (4, 0),
    // HPR / VPR aliases.
    test_hpr_moves_cursor_right: start (5, 10), b"\x1b[5a" => (5, 15),
    test_hpr_default_is_1: start (0, 20), b"\x1b[a" => (0, 21),
    test_vpr_moves_cursor_down: start (5, 10), b"\x1b[3e" => (8, 10),
    test_vpr_default_is_1: start (5, 0), b"\x1b[e" => (6, 0),
    // Extra regression cases around the same cursor helpers.
    test_cup_default_row_only: start (10, 30), b"\x1b[;5H" => (0, 4),
    test_cuu_multi_row_from_middle: start (10, 20), b"\x1b[3A" => (7, 20),
    test_cuf_multi_column_from_middle: start (7, 10), b"\x1b[5C" => (7, 15),
    test_cub_explicit_zero_treated_as_1: start (0, 5), b"\x1b[0D" => (0, 4),
    test_cuu_clamps_already_at_top_with_large_n: start (0, 0), b"\x1b[1000A" => (0, 0),
    test_cuf_clamps_already_at_right_with_large_n: start (0, 79), b"\x1b[1000C" => (0, 79),
}

test_decscusr! {
    // param 0 -> BlinkingBlock (0 is alias for 1/default)
    test_decscusr_blinking_block_param0:
        b"\x1b[6 q", b"\x1b[0 q" => BlinkingBlock, "DECSCUSR 0 should set BlinkingBlock",
    // param 1 -> BlinkingBlock
    test_decscusr_blinking_block_param1:
        b"\x1b[4 q", b"\x1b[1 q" => BlinkingBlock, "DECSCUSR 1 should set BlinkingBlock",
    // param 2 -> SteadyBlock
    test_decscusr_steady_block:
        b"\x1b[5 q", b"\x1b[2 q" => SteadyBlock, "DECSCUSR 2 should set SteadyBlock",
    // param 3 -> BlinkingUnderline
    test_decscusr_blinking_underline:
        b"\x1b[2 q", b"\x1b[3 q" => BlinkingUnderline, "DECSCUSR 3 should set BlinkingUnderline",
    // param 4 -> SteadyUnderline
    test_decscusr_steady_underline:
        b"\x1b[1 q", b"\x1b[4 q" => SteadyUnderline, "DECSCUSR 4 should set SteadyUnderline",
    // param 5 -> BlinkingBar
    test_decscusr_blinking_bar:
        b"\x1b[2 q", b"\x1b[5 q" => BlinkingBar, "DECSCUSR 5 should set BlinkingBar",
    // param 6 -> SteadyBar
    test_decscusr_steady_bar:
        b"\x1b[1 q", b"\x1b[6 q" => SteadyBar, "DECSCUSR 6 should set SteadyBar",
    // unknown param -> BlinkingBlock fallback
    test_decscusr_unknown_param_defaults_to_blinking_block:
        b"\x1b[6 q", b"\x1b[99 q" => BlinkingBlock,
        "DECSCUSR with unrecognised param should fall back to BlinkingBlock",
}

#[test]
fn test_cpl_nix_progress_pattern() {
    // Simulate the nix progress overwrite pattern:
    // 1. Print 3 progress lines
    // 2. CPL 3 to go back to the first one
    // 3. Overwrite them
    let mut term = crate::TerminalCore::new(24, 80);

    // Print 3 lines of "progress"
    term.advance(b"line1\nline2\nline3\n");
    // Cursor is now at row 3, col 0

    // CPL 3: go back 3 lines to row 0, col 0
    term.advance(b"\x1b[3F");

    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 0);

    // Overwrite line 1 with new content
    term.advance(b"updated1");
    assert_eq!(term.screen.cursor.row, 0);
    assert_eq!(term.screen.cursor.col, 8);
}
