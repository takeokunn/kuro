//! OSC sequence tests.

use std::sync::Arc;
use super::super::*;

#[test]
fn test_osc_title_set() {
    let mut core = super::make_term();
    assert_eq!(core.meta.title, "");
    assert!(!core.meta.title_dirty);

    core.advance(b"\x1b]2;hello tmux\x07");
    assert_eq!(core.meta.title, "hello tmux");
    assert!(core.meta.title_dirty);
}

#[test]
fn test_osc_icon_and_title() {
    let mut core = super::make_term();
    core.advance(b"\x1b]0;test title\x07");
    assert_eq!(core.meta.title, "test title");
    assert!(core.meta.title_dirty);
}

#[test]
fn test_osc_empty_ignored() {
    let mut core = super::make_term();
    core.advance(b"\x1b]2;\x07");
    assert_eq!(core.meta.title, "");
    assert!(!core.meta.title_dirty);
}

#[test]
fn test_osc_title_st_terminator() {
    // ST-terminated (ESC \) should be handled identically to BEL
    let mut core = super::make_term();
    core.advance(b"\x1b]2;st term title\x1b\\");
    assert_eq!(core.meta.title, "st term title");
    assert!(core.meta.title_dirty);
}

#[test]
fn test_osc_title_reset_clears() {
    let mut core = super::make_term();
    core.advance(b"\x1b]2;before reset\x07");
    assert!(core.meta.title_dirty);
    core.reset(); // RIS ESC c
    assert_eq!(core.meta.title, "");
    assert!(!core.meta.title_dirty);
}

#[test]
fn test_osc_title_atomic_clear() {
    // Verify that title_dirty is cleared after being read, and the title value is correct.
    let mut core = super::make_term();

    core.advance(b"\x1b]2;test title\x07");
    assert!(
        core.meta.title_dirty,
        "title_dirty should be set after OSC dispatch"
    );
    assert_eq!(core.meta.title, "test title");

    // Simulate the atomic-clear: read title, then clear dirty flag
    let read_title = core.meta.title.clone();
    core.meta.title_dirty = false;

    assert_eq!(read_title, "test title");
    assert!(
        !core.meta.title_dirty,
        "title_dirty should be false after atomic clear"
    );

    // Verify a second dispatch sets dirty again
    core.advance(b"\x1b]2;new title\x07");
    assert!(
        core.meta.title_dirty,
        "title_dirty should be set again after second dispatch"
    );
    assert_eq!(core.meta.title, "new title");
}

#[test]
fn test_osc_title_length_cap() {
    // Verify that oversized OSC titles are silently ignored
    let mut core = super::make_term();

    // Title within limit should work (1024 'a' chars)
    let mut ok_seq = b"\x1b]2;".to_vec();
    ok_seq.extend_from_slice(&vec![b'a'; 1024]);
    ok_seq.push(0x07);
    core.advance(&ok_seq);
    assert!(core.meta.title_dirty, "1024-byte title should be accepted");
    core.meta.title_dirty = false;

    // Title over limit should be ignored (1025 'a' chars)
    let mut big_seq = b"\x1b]2;".to_vec();
    big_seq.extend_from_slice(&vec![b'a'; 1025]);
    big_seq.push(0x07);
    core.advance(&big_seq);
    assert!(!core.meta.title_dirty, "1025-byte title should be rejected");
}

#[test]
fn test_osc_title_non_utf8() {
    // Verify that non-UTF8 bytes are handled via lossy conversion (U+FFFD replacement)
    let mut core = super::make_term();
    core.advance(b"\x1b]2;hello\xff\xfeworld\x07");
    assert!(
        core.meta.title_dirty,
        "Non-UTF8 title should still set dirty"
    );
    assert!(
        !core.meta.title.is_empty(),
        "Non-UTF8 title should produce non-empty result via lossy conversion"
    );
    // Should not panic — if we got here, test passes
}

#[test]
fn test_osc_7_stores_cwd() {
    let mut core = super::make_term();
    core.advance(b"\x1b]7;file://localhost/tmp/test\x07");
    assert!(core.osc_data.cwd_dirty);
    assert_eq!(core.osc_data.cwd, Some("/tmp/test".to_owned()));
}

#[test]
fn test_osc_133_stores_prompt_marks() {
    let mut core = super::make_term();
    core.advance(b"\x1b]133;A\x07");
    assert_eq!(core.osc_data.prompt_marks.len(), 1);
    assert_eq!(
        core.osc_data.prompt_marks[0].mark,
        types::osc::PromptMark::PromptStart
    );
}

#[test]
fn test_osc_8_hyperlink() {
    let mut core = super::make_term();
    core.advance(b"\x1b]8;;https://example.com\x07");
    assert_eq!(
        core.osc_data.hyperlink.uri,
        Some(Arc::from("https://example.com"))
    );
    // Close hyperlink
    core.advance(b"\x1b]8;;\x07");
    assert!(core.osc_data.hyperlink.uri.is_none());
}

#[test]
fn test_osc_104_clears_palette() {
    let mut core = super::make_term();
    core.advance(b"\x1b]104\x07");
    assert!(core.osc_data.palette_dirty);
}
