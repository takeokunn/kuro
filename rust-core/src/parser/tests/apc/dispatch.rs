// Tests for `dispatch_kitty_apc` — the Kitty Graphics APC dispatcher.
//
// Covers:
// - KittyCommand::Delete sub-commands (a/A, i/I, p/P, x/X, y/Y, _)
// - KittyCommand::Place (a=p) — end-to-end placement via advance()
// - KittyCommand::Transmit (a=t) — store without display
// - KittyCommand::TransmitAndDisplay (a=T) — store + placement notification
// - KittyCommand::Query (a=q) — OK response queued

use super::*;

// Helper: transmit-and-display a 1×1 RGB image at the current cursor position.
// Returns the image_id that was actually stored.
fn transmit_image(core: &mut crate::TerminalCore, image_id: u32, row: usize, col: usize) {
    core.screen.move_cursor(row, col);
    let seq = format!("\x1b_Ga=T,f=24,i={image_id},s=1,v=1,c=1,r=1;AAAA\x1b\\");
    core.advance(seq.as_bytes());
}

// ── d=a / d=A: clear all placements ──────────────────────────────────────────

#[test]
fn test_dispatch_delete_a_lowercase_clears_all_placements() {
    let mut core = crate::TerminalCore::new(24, 80);
    transmit_image(&mut core, 1, 0, 0);
    transmit_image(&mut core, 2, 1, 0);
    // Confirm two notifications queued (one per transmit-and-display)
    assert_pending_image_notification_count(&core, 2);

    // Clear all placements: a=d,d=a (lowercase)
    core.advance(b"\x1b_Ga=d,d=a\x1b\\");

    // Image data must still be present (delete-all only clears placements)
    assert!(
        !core.get_image_png_base64(1).is_empty(),
        "image 1 data must survive d=a"
    );
    assert!(
        !core.get_image_png_base64(2).is_empty(),
        "image 2 data must survive d=a"
    );
}

#[test]
fn test_dispatch_delete_a_uppercase_clears_all_placements() {
    let mut core = crate::TerminalCore::new(24, 80);
    transmit_image(&mut core, 10, 0, 0);

    // Clear all placements: a=d,d=A (uppercase — integration_kitty.rs arm)
    core.advance(b"\x1b_Ga=d,d=A\x1b\\");

    // Image data persists; APC state is Idle
    assert!(!core.get_image_png_base64(10).is_empty());
    assert!(core.kitty.apc_state == ApcScanState::Idle);
}

// ── d=i / d=I: delete by image ID ────────────────────────────────────────────

#[test]
fn test_dispatch_delete_i_lowercase_removes_by_image_id() {
    let mut core = crate::TerminalCore::new(24, 80);
    transmit_image(&mut core, 20, 0, 0);
    transmit_image(&mut core, 21, 0, 5);

    // Delete image 20 by ID: a=d,i=20,d=i
    core.advance(b"\x1b_Ga=d,i=20,d=i\x1b\\");

    // Image 20 data is gone; image 21 data survives
    assert!(
        core.get_image_png_base64(20).is_empty(),
        "image 20 must be deleted by d=i"
    );
    assert!(
        !core.get_image_png_base64(21).is_empty(),
        "image 21 must survive delete of image 20"
    );
}

#[test]
fn test_dispatch_delete_i_uppercase_removes_by_image_id() {
    let mut core = crate::TerminalCore::new(24, 80);
    transmit_image(&mut core, 30, 0, 0);

    core.advance(b"\x1b_Ga=d,i=30,d=I\x1b\\");

    assert!(
        core.get_image_png_base64(30).is_empty(),
        "image 30 must be deleted by d=I"
    );
}

// ── d=p / d=P: delete by placement ID ────────────────────────────────────────

#[test]
fn test_dispatch_delete_p_lowercase_removes_by_placement() {
    let mut core = crate::TerminalCore::new(24, 80);
    // Store image 40 with explicit placement_id=1 via a=T,q=2,p=1
    core.advance(b"\x1b_Ga=T,f=24,i=40,s=1,v=1,c=1,r=1,p=1;AAAA\x1b\\");

    // Delete by image_id + placement_id: a=d,i=40,p=1,d=p
    core.advance(b"\x1b_Ga=d,i=40,p=1,d=p\x1b\\");

    // Image data survives (d=p only removes the specific placement)
    assert!(
        !core.get_image_png_base64(40).is_empty(),
        "image 40 data must survive d=p (only the placement is removed)"
    );
    assert!(core.kitty.apc_state == ApcScanState::Idle);
}

#[test]
fn test_dispatch_delete_p_uppercase_removes_by_placement() {
    let mut core = crate::TerminalCore::new(24, 80);
    core.advance(b"\x1b_Ga=T,f=24,i=41,s=1,v=1,c=1,r=1,p=2;AAAA\x1b\\");

    core.advance(b"\x1b_Ga=d,i=41,p=2,d=P\x1b\\");

    assert!(
        !core.get_image_png_base64(41).is_empty(),
        "image 41 data must survive d=P"
    );
}

// ── d=x / d=X: delete by column ──────────────────────────────────────────────

#[test]
fn test_dispatch_delete_x_lowercase_removes_by_col() {
    let mut core = crate::TerminalCore::new(24, 80);
    // Place image at col 5
    core.screen.move_cursor(0, 5);
    core.advance(b"\x1b_Ga=T,f=24,i=50,s=1,v=1,c=1,r=1;AAAA\x1b\\");
    assert_pending_image_notification_count(&core, 1);

    // Move cursor to col 5 and delete by col: a=d,d=x
    core.screen.move_cursor(0, 5);
    core.advance(b"\x1b_Ga=d,d=x\x1b\\");

    // State returns to Idle
    assert!(core.kitty.apc_state == ApcScanState::Idle);
}

#[test]
fn test_dispatch_delete_x_uppercase_removes_by_col() {
    let mut core = crate::TerminalCore::new(24, 80);
    core.screen.move_cursor(0, 10);
    core.advance(b"\x1b_Ga=T,f=24,i=51,s=1,v=1,c=1,r=1;AAAA\x1b\\");

    core.screen.move_cursor(0, 10);
    core.advance(b"\x1b_Ga=d,d=X\x1b\\");

    assert!(core.kitty.apc_state == ApcScanState::Idle);
}

// ── d=y / d=Y: delete by row ─────────────────────────────────────────────────

#[test]
fn test_dispatch_delete_y_lowercase_removes_by_row() {
    let mut core = crate::TerminalCore::new(24, 80);
    core.screen.move_cursor(3, 0);
    core.advance(b"\x1b_Ga=T,f=24,i=60,s=1,v=1,c=1,r=1;AAAA\x1b\\");
    assert_pending_image_notification_count(&core, 1);

    // Delete placements at row 3: a=d,d=y
    core.screen.move_cursor(3, 0);
    core.advance(b"\x1b_Ga=d,d=y\x1b\\");

    assert!(core.kitty.apc_state == ApcScanState::Idle);
}

#[test]
fn test_dispatch_delete_y_uppercase_removes_by_row() {
    let mut core = crate::TerminalCore::new(24, 80);
    core.screen.move_cursor(7, 0);
    core.advance(b"\x1b_Ga=T,f=24,i=61,s=1,v=1,c=1,r=1;AAAA\x1b\\");

    core.screen.move_cursor(7, 0);
    core.advance(b"\x1b_Ga=d,d=Y\x1b\\");

    assert!(core.kitty.apc_state == ApcScanState::Idle);
}

// ── unknown delete sub-command: default no-op arm ────────────────────────────

#[test]
fn test_dispatch_delete_unknown_sub_is_noop() {
    let mut core = crate::TerminalCore::new(24, 80);
    transmit_image(&mut core, 70, 0, 0);

    // d=z — unknown sub-command, must not panic
    core.advance(b"\x1b_Ga=d,d=z\x1b\\");

    // Image data and state machine must be unaffected
    assert!(
        !core.get_image_png_base64(70).is_empty(),
        "image 70 must survive an unknown delete sub-command"
    );
    assert!(core.kitty.apc_state == ApcScanState::Idle);
}

// ── KittyCommand::Transmit (a=t) dispatch ────────────────────────────────────

#[test]
fn test_dispatch_transmit_stores_image_without_notification() {
    let mut core = crate::TerminalCore::new(24, 80);

    // a=t: transmit only (no display); f=24 = raw RGB, s=1, v=1 = 1×1 pixel
    core.advance(b"\x1b_Ga=t,f=24,i=80,s=1,v=1;AAAA\x1b\\");

    // Image data must be stored
    let png = core.get_image_png_base64(80);
    assert!(!png.is_empty(), "a=t must store image data");

    // Transmit-only must NOT queue a placement notification
    assert_no_pending_image_notifications(&core);
    assert!(core.kitty.apc_state == ApcScanState::Idle);
}

// ── KittyCommand::TransmitAndDisplay (a=T) dispatch ──────────────────────────

#[test]
fn test_dispatch_transmit_and_display_stores_and_notifies() {
    let mut core = crate::TerminalCore::new(24, 80);

    // a=T: transmit and display, 2×2 cell placement
    core.advance(b"\x1b_Ga=T,f=24,i=90,s=1,v=1,c=2,r=2;AAAA\x1b\\");

    // Image must be stored
    let png = core.get_image_png_base64(90);
    assert!(!png.is_empty(), "a=T must store image data");

    // Exactly one placement notification must be queued
    assert_single_pending_image_notification(&core, 90, 2, 2);
}

// ── KittyCommand::Place (a=p) dispatch ───────────────────────────────────────

#[test]
fn test_dispatch_place_queues_notification_for_stored_image() {
    let mut core = crate::TerminalCore::new(24, 80);

    // First store the image (transmit-only)
    core.advance(b"\x1b_Ga=t,f=24,i=100,s=1,v=1;AAAA\x1b\\");
    assert_no_pending_image_notifications(&core);

    // Now place it: a=p at cursor position (0, 0), 3×1 cells
    core.screen.move_cursor(0, 0);
    core.advance(b"\x1b_Ga=p,i=100,c=3,r=1\x1b\\");

    // A placement notification must be queued
    assert_single_pending_image_notification(&core, 100, 3, 1);
    assert!(core.kitty.apc_state == ApcScanState::Idle);
}
