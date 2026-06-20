//! End-to-end tests for the full Kitty `a=d` delete-target list driven through
//! `TerminalCore::advance` (the real APC dispatch path).
//!
//! Module under test: `parser/apc.rs` (`handle_kitty_delete`).

use super::*;

/// Transmit-and-display a 1×1 RGB image at (row, col) with `cols`×`rows` cells
/// and optional z-index.
fn place_image(
    core: &mut crate::TerminalCore,
    image_id: u32,
    row: usize,
    col: usize,
    cols: u32,
    rows: u32,
    z: i32,
) {
    core.screen.move_cursor(row, col);
    let seq = format!("\x1b_Ga=T,f=24,i={image_id},s=1,v=1,c={cols},r={rows},z={z};AAAA\x1b\\");
    core.advance(seq.as_bytes());
}

fn placement_count(core: &crate::TerminalCore) -> usize {
    core.screen.active_graphics().placement_count()
}

// --- d=z : by z-index ---

/// INTENT: `a=d,d=z,z=N` removes placements at that z-layer; data survives.
#[test]
fn delete_z_lowercase_removes_layer_keeps_image() {
    let mut core = crate::TerminalCore::new(24, 80);
    place_image(&mut core, 1, 0, 0, 1, 1, 3);
    place_image(&mut core, 1, 0, 1, 1, 1, 8);

    core.advance(b"\x1b_Ga=d,d=z,z=3\x1b\\");

    assert_eq!(placement_count(&core), 1);
    assert!(!core.get_image_png_base64(1).is_empty(), "image survives d=z");
}

/// INTENT: `a=d,d=Z` (uppercase) frees the backing image data.
#[test]
fn delete_z_uppercase_frees_image() {
    let mut core = crate::TerminalCore::new(24, 80);
    place_image(&mut core, 2, 0, 0, 1, 1, 4);

    core.advance(b"\x1b_Ga=d,d=Z,z=4\x1b\\");

    assert!(core.get_image_png_base64(2).is_empty(), "d=Z frees image data");
}

// --- d=p : at cell (x=,y=) ---

/// INTENT: `a=d,d=p,x=col,y=row` removes a placement covering that cell.
#[test]
fn delete_p_at_cell_removes_covering_placement() {
    let mut core = crate::TerminalCore::new(24, 80);
    // 3×2 image at (row 2, col 5): covers rows 2..4, cols 5..7.
    place_image(&mut core, 3, 2, 5, 3, 2, 0);

    // Target cell (row 3, col 6) → x=6, y=3.
    core.advance(b"\x1b_Ga=d,d=p,x=6,y=3\x1b\\");

    assert_eq!(placement_count(&core), 0, "covering placement removed");
}

// --- d=q : at cell with z ---

/// INTENT: `a=d,d=q,x=,y=,z=` removes only the matching-z covering placement.
#[test]
fn delete_q_at_cell_with_z() {
    let mut core = crate::TerminalCore::new(24, 80);
    place_image(&mut core, 4, 0, 0, 2, 2, 5);
    place_image(&mut core, 4, 0, 0, 2, 2, 9);

    core.advance(b"\x1b_Ga=d,d=q,x=0,y=0,z=5\x1b\\");

    assert_eq!(placement_count(&core), 1, "only z=5 layer removed");
}

// --- d=x : intersecting column ---

/// INTENT: `a=d,d=x,x=col` removes placements intersecting that column.
#[test]
fn delete_x_intersecting_col() {
    let mut core = crate::TerminalCore::new(24, 80);
    // width 4 at col 2 → covers cols 2..6.
    place_image(&mut core, 5, 0, 2, 4, 1, 0);
    place_image(&mut core, 5, 0, 20, 1, 1, 0);

    core.advance(b"\x1b_Ga=d,d=x,x=5\x1b\\");

    assert_eq!(placement_count(&core), 1);
}

// --- d=y : intersecting row ---

/// INTENT: `a=d,d=y,y=row` removes placements intersecting that row.
#[test]
fn delete_y_intersecting_row() {
    let mut core = crate::TerminalCore::new(24, 80);
    // height 3 at row 4 → covers rows 4..7.
    place_image(&mut core, 6, 4, 0, 1, 3, 0);
    place_image(&mut core, 6, 20, 0, 1, 1, 0);

    core.advance(b"\x1b_Ga=d,d=y,y=6\x1b\\");

    assert_eq!(placement_count(&core), 1);
}

// --- d=n : newest by number (I=) ---

/// INTENT: `a=d,d=n` deletes placements of the most-recently stored image.
#[test]
fn delete_n_newest_no_number() {
    let mut core = crate::TerminalCore::new(24, 80);
    place_image(&mut core, 1, 0, 0, 1, 1, 0);
    place_image(&mut core, 9, 0, 1, 1, 1, 0); // highest id

    core.advance(b"\x1b_Ga=d,d=n\x1b\\");

    assert!(!core.get_image_png_base64(1).is_empty(), "image 1 survives");
    assert_eq!(placement_count(&core), 1, "newest (id 9) placement removed");
}

/// INTENT: `a=d,d=N,I=num` (uppercase) frees the numbered image's data.
#[test]
fn delete_n_uppercase_with_number_frees_image() {
    let mut core = crate::TerminalCore::new(24, 80);
    place_image(&mut core, 7, 0, 0, 1, 1, 0);

    core.advance(b"\x1b_Ga=d,d=N,I=7\x1b\\");

    assert!(core.get_image_png_base64(7).is_empty(), "d=N frees image 7");
}

// --- d=c : at cursor ---

/// INTENT: `a=d,d=c` removes placements covering the cursor cell.
#[test]
fn delete_c_at_cursor() {
    let mut core = crate::TerminalCore::new(24, 80);
    place_image(&mut core, 8, 5, 5, 2, 2, 0); // covers (5,5)..(6,6)

    core.screen.move_cursor(6, 6);
    core.advance(b"\x1b_Ga=d,d=c\x1b\\");

    assert_eq!(placement_count(&core), 0, "cursor-covered placement removed");
}

// --- d=r : id range (x=min, y=max) ---

/// INTENT: `a=d,d=r,x=min,y=max` removes placements whose id is in range.
#[test]
fn delete_r_id_range() {
    let mut core = crate::TerminalCore::new(24, 80);
    place_image(&mut core, 10, 0, 0, 1, 1, 0);
    place_image(&mut core, 11, 1, 0, 1, 1, 0);
    place_image(&mut core, 12, 2, 0, 1, 1, 0);

    core.advance(b"\x1b_Ga=d,d=r,x=11,y=12\x1b\\");

    assert!(!core.get_image_png_base64(10).is_empty(), "id 10 survives");
    assert_eq!(placement_count(&core), 1, "ids 11,12 placements removed");
}

/// INTENT: `a=d,d=R` (uppercase) range frees image data in range.
#[test]
fn delete_r_uppercase_frees_range() {
    let mut core = crate::TerminalCore::new(24, 80);
    place_image(&mut core, 10, 0, 0, 1, 1, 0);
    place_image(&mut core, 11, 1, 0, 1, 1, 0);

    core.advance(b"\x1b_Ga=d,d=R,x=10,y=11\x1b\\");

    assert!(core.get_image_png_base64(10).is_empty(), "id 10 freed");
    assert!(core.get_image_png_base64(11).is_empty(), "id 11 freed");
}
