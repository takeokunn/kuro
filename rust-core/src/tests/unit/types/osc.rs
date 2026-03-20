//! Unit tests for `crate::types::osc` (`OscData`, `HyperlinkState`, `PromptMark`, `ClipboardAction`).

use crate::types::osc::{ClipboardAction, HyperlinkState, OscData, PromptMark, PromptMarkEvent};
use crate::types::color::Color;
use proptest::prelude::*;

// ---------------------------------------------------------------------------
// OscData::default() construction
// ---------------------------------------------------------------------------

#[test]
fn osc_data_default_cwd_is_none() {
    let d = OscData::default();
    assert!(d.cwd.is_none(), "cwd must be None on construction");
}

#[test]
fn osc_data_default_cwd_dirty_is_false() {
    let d = OscData::default();
    assert!(!d.cwd_dirty, "cwd_dirty must be false on construction");
}

#[test]
fn osc_data_default_hyperlink_uri_is_none() {
    let d = OscData::default();
    assert!(
        d.hyperlink.uri.is_none(),
        "hyperlink.uri must be None on construction"
    );
}

#[test]
fn osc_data_default_colors_are_none() {
    let d = OscData::default();
    assert!(d.default_fg.is_none(), "default_fg must be None");
    assert!(d.default_bg.is_none(), "default_bg must be None");
    assert!(d.cursor_color.is_none(), "cursor_color must be None");
}

#[test]
fn osc_data_default_prompt_marks_empty() {
    let d = OscData::default();
    assert!(d.prompt_marks.is_empty(), "prompt_marks must be empty on construction");
}

#[test]
fn osc_data_palette_has_256_entries() {
    let d = OscData::default();
    assert_eq!(d.palette.len(), 256, "palette must have exactly 256 entries");
}

#[test]
fn osc_data_palette_all_none_on_default() {
    let d = OscData::default();
    assert!(
        d.palette.iter().all(std::option::Option::is_none),
        "every palette entry must be None on construction"
    );
}

#[test]
fn osc_data_set_palette_entry() {
    let mut d = OscData::default();
    d.palette[42] = Some([0xDE, 0xAD, 0xBE]);
    assert_eq!(d.palette[42], Some([0xDE, 0xAD, 0xBE]));
    // All others remain None
    for (i, e) in d.palette.iter().enumerate() {
        if i != 42 {
            assert!(e.is_none(), "palette[{i}] must still be None");
        }
    }
}

// ---------------------------------------------------------------------------
// HyperlinkState
// ---------------------------------------------------------------------------

#[test]
fn hyperlink_state_default_uri_none() {
    let h = HyperlinkState::default();
    assert!(h.uri.is_none());
}

#[test]
fn hyperlink_state_set_uri() {
    let h = HyperlinkState { uri: Some("https://example.com".to_string()) };
    assert_eq!(h.uri.as_deref(), Some("https://example.com"));
}

#[test]
fn hyperlink_state_clear_uri() {
    let mut h = HyperlinkState { uri: Some("https://example.com".to_string()) };
    h.uri = None;
    assert!(h.uri.is_none());
}

// ---------------------------------------------------------------------------
// PromptMark variants
// ---------------------------------------------------------------------------

#[test]
fn prompt_mark_variants_are_distinct() {
    assert_ne!(PromptMark::PromptStart, PromptMark::PromptEnd);
    assert_ne!(PromptMark::CommandStart, PromptMark::CommandEnd);
    assert_ne!(PromptMark::PromptStart, PromptMark::CommandStart);
}

#[test]
fn prompt_mark_event_fields_accessible() {
    // PromptMarkEvent fields are pub(crate) — accessible inside the crate.
    let event = PromptMarkEvent {
        mark: PromptMark::PromptStart,
        row: 5,
        col: 10,
    };
    assert!(matches!(event.mark, PromptMark::PromptStart));
    assert_eq!(event.row, 5);
    assert_eq!(event.col, 10);
}

#[test]
fn osc_data_push_prompt_mark() {
    let mut d = OscData::default();
    d.prompt_marks.push(PromptMarkEvent {
        mark: PromptMark::CommandEnd,
        row: 3,
        col: 0,
    });
    assert_eq!(d.prompt_marks.len(), 1);
    assert!(matches!(d.prompt_marks[0].mark, PromptMark::CommandEnd));
}

// ---------------------------------------------------------------------------
// ClipboardAction
// ---------------------------------------------------------------------------

#[test]
fn clipboard_action_write_stores_text() {
    let action = ClipboardAction::Write("hello clipboard".to_string());
    match action {
        ClipboardAction::Write(ref s) => assert_eq!(s, "hello clipboard"),
        ClipboardAction::Query => panic!("expected Write"),
    }
}

#[test]
fn clipboard_action_query_variant() {
    let action = ClipboardAction::Query;
    assert!(matches!(action, ClipboardAction::Query));
}

// ---------------------------------------------------------------------------
// OscData — color field mutation
// ---------------------------------------------------------------------------

#[test]
fn osc_data_set_default_fg() {
    let d = OscData { default_fg: Some(Color::Indexed(1)), ..Default::default() };
    assert!(matches!(d.default_fg, Some(Color::Indexed(1))));
}

#[test]
fn osc_data_set_default_bg() {
    let d = OscData { default_bg: Some(Color::Rgb(255, 128, 0)), ..Default::default() };
    assert!(matches!(d.default_bg, Some(Color::Rgb(255, 128, 0))));
}

#[test]
fn osc_data_set_cursor_color() {
    let d = OscData { cursor_color: Some(Color::Default), ..Default::default() };
    assert!(matches!(d.cursor_color, Some(Color::Default)));
}

// ---------------------------------------------------------------------------
// PBT: palette always has 256 entries
// ---------------------------------------------------------------------------

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    // INVARIANT: palette always has 256 entries regardless of which index is written
    fn prop_palette_always_256_entries(idx in 0usize..256usize, r in 0u8..=255u8, g in 0u8..=255u8, b in 0u8..=255u8) {
        let mut d = OscData::default();
        d.palette[idx] = Some([r, g, b]);
        prop_assert_eq!(d.palette.len(), 256);
    }

    #[test]
    // INVARIANT: written palette entry is read back correctly
    fn prop_palette_entry_roundtrip(idx in 0usize..256usize, r in 0u8..=255u8, g in 0u8..=255u8, b in 0u8..=255u8) {
        let mut d = OscData::default();
        d.palette[idx] = Some([r, g, b]);
        prop_assert_eq!(d.palette[idx], Some([r, g, b]));
    }

    #[test]
    // INVARIANT: HyperlinkState uri survives clone
    fn prop_hyperlink_clone_preserves_uri(len in 0usize..128usize) {
        let uri: String = "x".repeat(len);
        let h = HyperlinkState { uri: if len == 0 { None } else { Some(uri) } };
        let cloned = h.clone();
        prop_assert_eq!(cloned.uri, h.uri);
    }
}
