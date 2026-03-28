// ── New edge-case tests ───────────────────────────────────────────────────────

// DSR (Device Status Report) tests

#[test]
fn test_dsr_param6_enqueues_cpr_response() {
    // CSI 6 n should push an ESC[row;colR response into pending_responses.
    let mut term = term!(24, 80);
    term.screen.move_cursor(4, 9); // row=5, col=10 in 1-indexed
    term.advance(b"\x1b[6n");
    assert_eq!(
        term.meta.pending_responses.len(),
        1,
        "DSR 6 must enqueue exactly one response"
    );
    assert_eq!(
        term.meta.pending_responses[0], b"\x1b[5;10R",
        "DSR 6 response must be ESC[row;colR (1-indexed)"
    );
}

#[test]
fn test_dsr_param6_at_origin_is_1_1() {
    // At (0,0) the 1-indexed response is ESC[1;1R.
    let mut term = term!(24, 80);
    term.advance(b"\x1b[6n");
    assert_eq!(term.meta.pending_responses[0], b"\x1b[1;1R");
}

#[test]
fn test_dsr_non_6_param_is_silent_noop() {
    // DSR with param 5 (operating status) is not implemented — must not enqueue anything.
    let mut term = term!(24, 80);
    term.advance(b"\x1b[5n");
    assert!(
        term.meta.pending_responses.is_empty(),
        "DSR 5 is unimplemented and must not enqueue a response"
    );
}

// Zero-parameter tests for CUU / CUD / CUF / CUB
// VT standard: 0 is treated identically to 1 (csi_param1! uses .max(1)).

#[test]
fn test_cuu_zero_param_treated_as_1() {
    // CSI 0 A — explicit zero must move up by 1
    let mut term = term!(24, 80);
    term.screen.move_cursor(5, 10);
    term.advance(b"\x1b[0A");
    assert_cursor!(term, 4, 10);
}

#[test]
fn test_cud_zero_param_treated_as_1() {
    // CSI 0 B — explicit zero must move down by 1
    let mut term = term!(24, 80);
    term.screen.move_cursor(5, 10);
    term.advance(b"\x1b[0B");
    assert_cursor!(term, 6, 10);
}

#[test]
fn test_cuf_zero_param_treated_as_1() {
    // CSI 0 C — explicit zero must move right by 1
    let mut term = term!(24, 80);
    term.screen.move_cursor(3, 10);
    term.advance(b"\x1b[0C");
    assert_cursor!(term, 3, 11);
}

// Corner-case: cursor at bottom-right, movement in each direction

#[test]
fn test_cuu_from_bottom_right_corner() {
    // CUU 3 from the bottom-right corner: row decreases, col stays at last col.
    let mut term = term!(10, 40);
    term.screen.move_cursor(9, 39);
    term.advance(b"\x1b[3A");
    assert_cursor!(term, 6, 39);
}

#[test]
fn test_cub_from_bottom_right_corner_clamps() {
    // CUB large-n from bottom-right: col clamps to 0, row unchanged.
    let mut term = term!(10, 40);
    term.screen.move_cursor(9, 39);
    term.advance(b"\x1b[999D");
    assert_cursor!(term, 9, 0);
}

// VPA / CHA zero-param behaviour

#[test]
fn test_vpa_zero_param_maps_to_first_row() {
    // CSI 0 d — zero is treated as 1 (1-indexed) → row 0 (0-indexed).
    // saturating_sub(1) on 0 yields 0.
    let mut term = term!(24, 80);
    term.screen.move_cursor(15, 5);
    term.advance(b"\x1b[0d");
    assert_cursor!(term, row = 0);
}

#[test]
fn test_cha_zero_param_maps_to_first_col() {
    // CSI 0 G — zero saturating_sub(1) = 0 → column 0.
    let mut term = term!(24, 80);
    term.screen.move_cursor(5, 30);
    term.advance(b"\x1b[0G");
    assert_cursor!(term, col = 0);
}

// Sequential movements

#[test]
fn test_sequential_cup_then_cuu() {
    // CUP to (8,20) then CUU 3 → row 4, col 19 (0-indexed).
    let mut term = term!(24, 80);
    term.advance(b"\x1b[8;20H"); // → (7, 19)
    term.advance(b"\x1b[3A"); // → (4, 19)
    assert_cursor!(term, 4, 19);
}

#[test]
fn test_sequential_cnl_then_cpl_returns_to_origin() {
    // CNL 4 from row 3 → row 7 col 0; CPL 4 → row 3 col 0.
    let mut term = term!(24, 80);
    term.screen.move_cursor(3, 25);
    term.advance(b"\x1b[4E"); // CNL 4 → row 7, col 0
    assert_cursor!(term, 7, 0);
    term.advance(b"\x1b[4F"); // CPL 4 → row 3, col 0
    assert_cursor!(term, 3, 0);
}
