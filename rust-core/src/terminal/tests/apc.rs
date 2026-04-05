//! APC scanner tests.

use crate::parser::limits::MAX_APC_PAYLOAD_BYTES;

#[test]
fn test_apc_payload_at_cap() {
    // Build an APC sequence: ESC _ <payload> ESC \
    // with exactly MAX_APC_PAYLOAD_BYTES bytes of payload
    let mut core = super::make_term();
    let mut input = vec![0x1b, b'_']; // ESC _
    input.extend(std::iter::repeat_n(b'X', MAX_APC_PAYLOAD_BYTES));
    input.extend_from_slice(b"\x1b\\"); // ESC \  (string terminator)
    core.advance(&input);
    // The buffer should have been consumed and APC processed
    assert_eq!(
        core.kitty.apc_buf.len(),
        0,
        "apc_buf should be cleared after full APC sequence"
    );
}

#[test]
fn test_apc_payload_exceeds_cap_is_truncated() {
    let mut core = super::make_term();
    let mut input = vec![0x1b, b'_']; // ESC _
                                      // Send MORE than the cap
    input.extend(std::iter::repeat_n(b'X', MAX_APC_PAYLOAD_BYTES + 100));
    input.extend_from_slice(b"\x1b\\"); // ESC \
    core.advance(&input);
    // Buffer should be cleared after processing, but during processing it was capped
    assert_eq!(
        core.kitty.apc_buf.len(),
        0,
        "apc_buf should be cleared after APC sequence completes"
    );
}

#[test]
fn test_apc_split_across_advance_calls() {
    let mut core = super::make_term();
    // Send APC open + part of payload in first call
    let part1 = b"\x1b_GHello";
    // Send rest of payload + close in second call
    let part2 = b" World\x1b\\";
    core.advance(part1);
    core.advance(part2);
    // After the sequence completes, apc_buf should be cleared
    assert_eq!(
        core.kitty.apc_buf.len(),
        0,
        "apc_buf should be cleared after split APC sequence"
    );
}

// === Wave 3.1: TDD Tests for Unified APC Handling (single-pass optimization) ===
// These tests verify behavior needed for merging APC pre-scanner into vte parser

/// Test: APC sequence followed by CSI sequence should process both correctly
/// This verifies that single-pass won't drop regular sequences
#[test]
fn test_apc_followed_by_csi_processes_both() {
    let mut core = super::make_term();
    // APC sequence (Kitty graphics query) + CSI sequence (cursor position)
    // CSI 5;10 H = CUP (cursor position) to row 5, col 10 (1-indexed)
    let input = b"\x1b_Ga=q\x1b\\\x1b[5;10H";
    core.advance(input);
    // APC should be processed (apc_buf cleared)
    assert_eq!(core.kitty.apc_buf.len(), 0, "APC should be fully processed");
    // CSI CUP should have moved cursor: row=5 (1-indexed) -> row 4 (0-indexed)
    // col=10 (1-indexed) -> col 9 (0-indexed)
    let cursor = core.screen.cursor();
    assert_eq!(
        cursor.row, 4,
        "CSI CUP row=5 (1-indexed) should set row to 4 (0-indexed)"
    );
    assert_eq!(
        cursor.col, 9,
        "CSI CUP col=10 (1-indexed) should set col to 9 (0-indexed)"
    );
}

/// Test: CSI sequence followed by APC should process both correctly
#[test]
fn test_csi_followed_by_apc_processes_both() {
    let mut core = super::make_term();
    // CSI sequence first, then APC
    let input = b"\x1b[2J\x1b_Ga=q\x1b\\";
    core.advance(input);
    // ED (clear screen) should have cleared the screen
    // Check that cursor moved to home position (0,0) after ED 2
    let cursor = core.screen.cursor();
    assert_eq!(cursor.row, 0, "ED 2 should move cursor to row 0");
    assert_eq!(cursor.col, 0, "ED 2 should move cursor to col 0");
    // APC should be processed
    assert_eq!(core.kitty.apc_buf.len(), 0, "APC should be fully processed");
}

/// Test: Multiple APC sequences in single `advance()` call
#[test]
fn test_multiple_apc_in_single_advance() {
    let mut core = super::make_term();
    // Two APC sequences in one buffer
    let input = b"\x1b_Ga=q\x1b\\\x1b_Ga=q\x1b\\";
    core.advance(input);
    // Both APCs should be processed, buffer should be clear
    assert_eq!(
        core.kitty.apc_buf.len(),
        0,
        "All APC sequences should be processed"
    );
}

/// Test: APC with embedded false ST (ESC + non-backslash)
#[test]
fn test_apc_with_false_esc_st() {
    let mut core = super::make_term();
    // APC with ESC X (not ST) embedded in payload - ESC should be kept in payload
    let input = b"\x1b_Gtest\x1bXmore\x1b\\";
    core.advance(input);
    // APC should complete and buffer should be cleared
    assert_eq!(
        core.kitty.apc_buf.len(),
        0,
        "APC with false ST should complete"
    );
}

/// Test: Mixed APC, CSI, and OSC in single buffer
#[test]
fn test_mixed_apc_csi_osc_single_buffer() {
    let mut core = super::make_term();
    // APC + CSI + OSC in one buffer
    let input = b"\x1b_Ga=q\x1b\\\x1b[1;1H\x1b]2;Title\x07";
    core.advance(input);
    // All sequences should be processed
    assert_eq!(core.kitty.apc_buf.len(), 0, "APC should be processed");
    assert_eq!(core.screen.cursor().row, 0, "CSI CUP should set cursor row");
    assert_eq!(core.screen.cursor().col, 0, "CSI CUP should set cursor col");
    assert!(core.meta.title_dirty, "OSC title should set dirty flag");
}

/// Test: APC split across 3 `advance()` calls
#[test]
fn test_apc_split_across_three_advance_calls() {
    let mut core = super::make_term();
    // Part 1: ESC _ (APC start)
    core.advance(b"\x1b_");
    assert_eq!(
        core.kitty.apc_buf.len(),
        0,
        "After ESC _, waiting for payload"
    );
    // Part 2: Payload
    core.advance(b"Ga=q,s=100");
    assert!(!core.kitty.apc_buf.is_empty(), "Payload should be buffered");
    // Part 3: ESC \ (ST terminator)
    core.advance(b"\x1b\\");
    assert_eq!(core.kitty.apc_buf.len(), 0, "APC should complete after ST");
}

/// Test: Non-APC DCS sequence passes through without interference
#[test]
fn test_dcs_sequence_not_affected_by_apc_scanner() {
    let mut core = super::make_term();
    // DCS sequence (ESC P ... ESC \) - different from APC (ESC _)
    let input = b"\x1bP$q\x1b\\";
    core.advance(input);
    // DCS should not trigger APC handling (apc_buf should remain empty)
    assert_eq!(
        core.kitty.apc_buf.len(),
        0,
        "DCS should not interfere with APC state"
    );
}

/// Test: APC with maximum payload size is handled without panic
#[test]
fn test_apc_maximum_payload_no_panic() {
    let mut core = super::make_term();
    let mut input = vec![0x1b, b'_'];
    // Payload with Kitty graphics header + max data
    input.push(b'G');
    input.extend(std::iter::repeat_n(b'A', MAX_APC_PAYLOAD_BYTES - 1));
    input.extend_from_slice(b"\x1b\\");
    // Should not panic
    core.advance(&input);
    assert_eq!(
        core.kitty.apc_buf.len(),
        0,
        "APC at max size should complete"
    );
}

/// Test: Rapid ESC sequences don't confuse APC scanner
#[test]
fn test_rapid_esc_sequences_apc_scanner() {
    let mut core = super::make_term();
    // Multiple ESCs without forming APC
    let input = b"\x1b\x1b\x1b[A";
    core.advance(input);
    // ESC [ A = CUU (cursor up) - should process correctly
    // apc_buf should be empty (no APC started)
    assert_eq!(
        core.kitty.apc_buf.len(),
        0,
        "Rapid ESCs should not start APC"
    );
}

// === Conditional APC scanning tests ===
// These tests verify correctness of conditional APC scanning with memchr

/// Test: Plain text without ESC should process without APC state changes
/// Verifies that memchr-based fast path doesn't miss any APC sequences
#[test]
fn test_plain_text_no_esc_no_apc_state_change() {
    let mut core = super::make_term();
    // Plain ASCII text - no ESC bytes
    core.advance(b"Hello, World! This is plain text without escape sequences.");
    // apc_state should remain Idle (we can check by ensuring apc_buf is empty)
    assert_eq!(
        core.kitty.apc_buf.len(),
        0,
        "No APC buffering for plain text"
    );
    // Text should be printed correctly
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'H');
}

/// Test: Large plain text (1KB) without ESC processes correctly
/// Verifies memchr fast path handles bulk data without state corruption
#[test]
fn test_large_plain_text_processes_correctly() {
    let mut core = super::make_term();
    // 1KB of plain text
    let plain_text: Vec<u8> = (b'A'..=b'Z').cycle().take(1024).collect();
    core.advance(&plain_text);
    // No APC state should be active
    assert_eq!(core.kitty.apc_buf.len(), 0);
    // First cell should have 'A'
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'A');
}

/// Test: Text with ESC only at end processes correctly
/// Verifies memchr finds ESC even at buffer boundary
#[test]
fn test_esc_at_buffer_end_detected() {
    let mut core = super::make_term();
    // Plain text + ESC at the very end (incomplete sequence)
    let input = b"Hello World\x1b";
    core.advance(input);
    // ESC should be consumed (no panic), and apc_buf should be empty since
    // we're in AfterEsc state waiting for next byte
    // The ESC alone starts state machine but doesn't buffer anything yet
    // After advance completes, we should have processed the text
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'H');
}

/// Test: Text with ESC only at start processes correctly
/// Verifies memchr finds ESC at position 0
#[test]
fn test_esc_at_buffer_start_detected() {
    let mut core = super::make_term();
    // ESC at start (incomplete APC start), then plain text
    let input = b"\x1b_Gtest"; // ESC _ G (APC start without terminator)
    core.advance(input);
    // Should be in InApc state, buffering "test"
    assert!(
        !core.kitty.apc_buf.is_empty(),
        "APC payload should be buffered"
    );
}

/// Test: Multiple ESC bytes in sequence
/// Verifies memchr doesn't miss ESC bytes in rapid succession
#[test]
fn test_multiple_esc_bytes_detected() {
    let mut core = super::make_term();
    // ESC ESC ESC (multiple escape bytes)
    core.advance(b"\x1b\x1b\x1b");
    // Should not panic, apc_buf should be empty (no APC formed)
    assert_eq!(core.kitty.apc_buf.len(), 0);
}

/// Test: APC with large payload split across two advance calls
/// Verifies state persistence when first call has ESC
#[test]
fn test_apc_split_large_payload() {
    let mut core = super::make_term();
    // First chunk: ESC _ G + 512 bytes
    let mut part1 = vec![0x1b, b'_', b'G'];
    part1.extend(std::iter::repeat_n(b'X', 512));
    core.advance(&part1);
    // Should be in InApc state with buffered payload
    assert!(core.kitty.apc_buf.len() > 500);

    // Second chunk: 512 more bytes + ESC \
    let mut part2: Vec<u8> = std::iter::repeat_n(b'Y', 512).collect();
    part2.extend_from_slice(b"\x1b\\");
    core.advance(&part2);
    // APC should complete
    assert_eq!(core.kitty.apc_buf.len(), 0);
}

/// Test: Plain text after incomplete APC continues correctly
#[test]
fn test_plain_text_after_incomplete_apc() {
    let mut core = super::make_term();
    // Start an APC (incomplete)
    core.advance(b"\x1b_Gtest");
    assert!(!core.kitty.apc_buf.is_empty());
    // Now send plain text (no ESC) - should still process correctly
    // Note: This will be added to the APC buffer since we're in InApc state
    core.advance(b"more");
    // Should be buffering (still in APC)
    assert!(core.kitty.apc_buf.len() > 4);
}

/// Test: Buffer with ESC in the middle
#[test]
fn test_esc_in_middle_detected() {
    let mut core = super::make_term();
    // Plain text + ESC _ G test ESC \ + more plain text
    let input = b"Before\x1b_Gtest\x1b\\After";
    core.advance(input);
    // APC should complete, all text processed
    assert_eq!(core.kitty.apc_buf.len(), 0);
    // "Before" should be at the start
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'B');
}

/// Test: Performance critical - 100KB plain text should not run APC scanner
/// This is a correctness test that also validates the optimization path
#[test]
fn test_100kb_plain_text_no_apc_overhead() {
    let mut core = super::make_term();
    // 100KB of plain text (no ESC)
    let plain: Vec<u8> = std::iter::repeat_n(b'X', 100 * 1024).collect();
    core.advance(&plain);
    // No APC state should be active
    assert_eq!(core.kitty.apc_buf.len(), 0);
    // First cell should be 'X' (wrapped many times)
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'X');
}

/// Test: Mixed content - plain + CSI + APC + plain
#[test]
fn test_mixed_content_all_sequences_processed() {
    let mut core = super::make_term();
    // Plain text + CSI (color) + APC + plain text
    let input = b"Start\x1b[31mRed\x1b[0m\x1b_Ga=q\x1b\\End";
    core.advance(input);
    // All sequences should process correctly
    assert_eq!(core.kitty.apc_buf.len(), 0, "APC should complete");
    // "Start" should be at position 0
    assert_eq!(core.get_cell(0, 0).unwrap().char(), 'S');
    // Should not have current bold (reset)
    assert!(!core
        .current_attrs
        .flags
        .contains(crate::types::cell::SgrFlags::BOLD));
}
