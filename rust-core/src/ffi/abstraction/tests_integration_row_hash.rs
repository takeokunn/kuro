use crate::ffi::abstraction::tests_unit::make_session;

// ---------------------------------------------------------------------------
// T-A-7: Row-hash skip tests
// ---------------------------------------------------------------------------

/// Test 1 — hash skip: unchanged rows are not re-emitted on the second poll.
///
/// After the first `get_dirty_lines_with_faces` call the row hashes are cached.
/// A second call with no further terminal input must return zero rows because
/// the dirty set is empty and no row content changed.
#[test]
fn test_row_hash_skip_unchanged_rows_not_re_emitted() {
    let mut session = make_session();

    // Write some colored content to row 0.
    session.core.advance(b"\x1b[31mHello\x1b[m");

    // First poll — rows are dirty, must be returned.
    let first = session.get_dirty_lines_with_faces();
    assert!(
        !first.is_empty(),
        "First poll must return dirty rows after writing content"
    );

    // Second poll — nothing changed; the dirty set is empty.
    // The row-hash skip should also prevent re-emission for any false positives.
    let second = session.get_dirty_lines_with_faces();
    assert!(
        second.is_empty(),
        "Second poll with no changes must return zero rows (hash skip active)"
    );
}

/// Test 1b — hash skip: changing a single cell causes only that row to be returned.
///
/// Write content, poll (caches hashes), then overwrite one row and poll again.
/// Only the modified row should appear in the second poll output.
#[test]
fn test_row_hash_skip_changed_row_returned() {
    let mut session = make_session();

    // Write content to rows 0 and 1.
    session.core.advance(b"Row zero\r\nRow one");

    // First poll — both rows dirty.
    let first = session.get_dirty_lines_with_faces();
    assert!(
        first.len() >= 2,
        "First poll must include both written rows, got {} rows",
        first.len()
    );

    // Move cursor to row 0, col 0 and overwrite it.
    session.core.advance(b"\x1b[1;1HChanged!");

    // Second poll — only row 0 changed; row 1 must be skipped.
    let second = session.get_dirty_lines_with_faces();
    assert!(
        !second.is_empty(),
        "Second poll must return the changed row"
    );
    let returned_rows: Vec<usize> = second.iter().map(|line| line.row).collect();
    assert!(
        returned_rows.contains(&0),
        "Row 0 must be returned after its content changed, got: {returned_rows:?}"
    );
    assert!(
        !returned_rows.contains(&1),
        "Row 1 must be skipped (content unchanged), got: {returned_rows:?}"
    );
}

/// Test 2 — resize invalidates: after a resize all rows must be re-returned.
///
/// Write content, poll once to cache hashes, then resize the terminal.
/// The resize must clear `row_hashes`, so the next poll returns all rows.
#[test]
fn test_row_hash_skip_resize_invalidates_cache() {
    let mut session = make_session();

    // Write content and poll once to populate the hash cache.
    session.core.advance(b"Hello World");
    let first = session.get_dirty_lines_with_faces();
    assert!(!first.is_empty(), "First poll must return dirty rows");

    // Resize the terminal (same rows, different cols to trigger the resize path).
    session
        .resize(24, 100)
        .expect("resize must not fail in test");

    // After resize the screen is fully dirty; all rows must be returned.
    let after_resize = session.get_dirty_lines_with_faces();
    assert!(
        !after_resize.is_empty(),
        "After resize, all rows must be returned (hash cache cleared)"
    );
    assert_eq!(
        after_resize.len(),
        24,
        "After resize the full screen (24 rows) must be returned"
    );
}

/// Test 3 — alternate screen: entering the alternate screen clears the hash cache.
///
/// Write content, poll once to cache hashes, then send ESC [?1049h (enter alt
/// screen).  The next poll must detect the screen switch and return all rows.
#[test]
fn test_row_hash_skip_alt_screen_enter_invalidates_cache() {
    let mut session = make_session();
    let session_rows = 24usize;

    // Write content to the primary screen and cache hashes.
    session.core.advance(b"Primary screen content");
    let first = session.get_dirty_lines_with_faces();
    assert!(!first.is_empty(), "First poll must return dirty rows");

    // Enter alternate screen (DEC 1049 enable).
    session.core.advance(b"\x1b[?1049h");

    // The alternate screen is newly blank and fully dirty.
    let after_enter = session.get_dirty_lines_with_faces();
    assert!(
        !after_enter.is_empty(),
        "Entering alternate screen must return all rows (hash cache cleared)"
    );
    assert_eq!(
        after_enter.len(),
        session_rows,
        "alt-screen enter should invalidate all row hashes and return all rows"
    );
}

/// Test 3b — alternate screen exit: leaving the alternate screen also clears hashes.
#[test]
fn test_row_hash_skip_alt_screen_exit_invalidates_cache() {
    let mut session = make_session();
    let session_rows = 24usize;

    // Enter alternate screen, write something, then poll to cache hashes.
    session.core.advance(b"\x1b[?1049h");
    session.core.advance(b"Alt screen content");
    let _alt_poll = session.get_dirty_lines_with_faces();

    // Exit alternate screen (DEC 1049 reset) — returns to primary screen.
    session.core.advance(b"\x1b[?1049l");

    // The primary screen is fully dirty after returning from alternate.
    let after_exit = session.get_dirty_lines_with_faces();
    assert!(
        !after_exit.is_empty(),
        "Exiting alternate screen must return all rows (hash cache cleared)"
    );
    assert_eq!(
        after_exit.len(),
        session_rows,
        "alt-screen exit should invalidate all row hashes and return all rows"
    );
}

/// Test 4 — palette epoch: an OSC 4 palette change invalidates the row-hash cache.
///
/// The palette_epoch mechanism works as follows:
/// 1. When `palette_dirty` is set (via OSC 4), `get_dirty_lines_with_faces`
///    bumps `palette_epoch` at the start of the next call.
/// 2. A cached row hash entry stores `(hash, epoch)`.  A row is skipped only
///    when both `hash == new_hash` AND `stored_epoch == current_epoch`.
/// 3. After a palette change, `palette_epoch` increases so `stored_epoch !=
///    epoch` for every previously-cached row.  Therefore, any row that is
///    also in the dirty set will be re-emitted despite its content hash being
///    unchanged (i.e. the palette change broke the cache).
///
/// This test exercises step 3: write content, cache hashes, confirm cache
/// hit, then send an OSC 4 palette change.  We then manually mark row 0
/// dirty (simulating a terminal that writes the same content after a palette
/// change) and verify it is re-emitted even though its cell content hash is
/// identical to the cached value.
#[test]
fn test_row_hash_skip_palette_epoch_invalidates_cache() {
    let mut session = make_session();

    // Step 1 & 2: Write colored content using named color 31 (red).
    session.core.advance(b"\x1b[31mHello\x1b[0m");

    // Step 3: First poll — rows are dirty; cache is seeded with epoch=0.
    let first = session.get_dirty_lines_with_faces();
    assert!(
        !first.is_empty(),
        "First poll must return dirty rows after writing colored content"
    );

    // Step 4: Second poll — no content change; palette_epoch unchanged → cache hit.
    let second = session.get_dirty_lines_with_faces();
    assert!(
        second.is_empty(),
        "Second poll with no changes must return zero rows (hash cache hit, palette_epoch unchanged)"
    );

    // Confirm row 0 is cached with epoch 0.
    assert!(
        session.row_hashes.first().copied().flatten().is_some(),
        "row_hashes must be populated after the first poll"
    );
    let stored_cache = session.row_hashes[0].expect("row 0 must be cached");
    assert_eq!(
        stored_cache.palette_epoch, 0,
        "Stored epoch must be 0 before any palette change"
    );

    // Step 5: Send an OSC 4 palette change for color index 1 to bright red.
    // OSC 4 ; 1 ; rgb:ff/00/00 ST  (ST = ESC \)
    // This sets `palette_dirty = true` without marking any screen rows dirty.
    session.core.advance(b"\x1b]4;1;rgb:ff/00/00\x1b\\");
    assert!(
        session.core.osc_data.palette_dirty,
        "palette_dirty must be true after OSC 4"
    );

    // Manually mark row 0 dirty to simulate a terminal redraw after palette change.
    // (Writing identical cell content does not re-mark a row dirty — the screen
    // optimises away no-op writes — so we use mark_line_dirty directly here.)
    session.core.screen.mark_line_dirty(0);

    // Step 6: Third poll — palette_epoch is bumped (palette_dirty consumed),
    // so the cached `stored_epoch (0) != current_epoch (1)` for row 0.
    // Row 0 must be re-emitted despite its content hash being unchanged.
    let third = session.get_dirty_lines_with_faces();
    assert!(
        !third.is_empty(),
        "After OSC 4 palette change, a dirty row must be re-emitted \
         (palette_epoch bump causes stored_epoch != current_epoch)"
    );

    // Verify the palette_epoch was indeed incremented.
    assert_eq!(
        session.palette_epoch, 1,
        "palette_epoch must be 1 after one OSC 4 palette change"
    );
}
