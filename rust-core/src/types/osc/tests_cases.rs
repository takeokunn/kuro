use super::tests_support::*;
use crate::types::color::Color;
use crate::types::osc::{
    ClipboardAction, DefaultColorSlot, HyperlinkState, OscData, PromptMark, SelectionTarget,
};

// -------------------------------------------------------------------------
// OscData construction
// -------------------------------------------------------------------------

#[test]
// CONSTRUCTION: OscData::default() must initialise all default fields consistently.
fn osc_data_default_state_is_empty() {
    let d = OscData::default();
    assert!(d.cwd.is_none(), "cwd must be None on construction");
    assert!(!d.cwd_dirty, "cwd_dirty must be false on construction");
    assert!(
        d.hyperlink.uri.is_none(),
        "hyperlink.uri must be None on construction"
    );
    assert!(d.default_fg.is_none(), "default_fg must be None");
    assert!(d.default_bg.is_none(), "default_bg must be None");
    assert!(d.cursor_color.is_none(), "cursor_color must be None");
    assert!(
        d.prompt_marks.is_empty(),
        "prompt_marks must be empty on construction"
    );
    assert!(
        d.clipboard_actions.is_empty(),
        "clipboard_actions must be empty on construction"
    );
}

#[test]
// CONSTRUCTION: OscData::default() palette must have exactly 256 None entries.
fn osc_data_default_palette_len_256_all_none() {
    let d = OscData::default();
    assert_eq!(d.palette.len(), 256);
    assert!(d.palette.iter().all(Option::is_none));
}

#[test]
// MUTATION: set_cwd() stores host/path together and marks the directory dirty.
fn osc_data_set_cwd_marks_dirty() {
    let mut d = OscData::default();
    d.set_cwd(
        Some("example.com".to_owned()),
        Some("/home/kuro".to_owned()),
    );
    assert_eq!(d.cwd_host.as_deref(), Some("example.com"));
    assert_eq!(d.cwd.as_deref(), Some("/home/kuro"));
    assert!(d.cwd_dirty);
}

#[test]
// MUTATION: set_hyperlink_uri() opens and clears OSC 8 hyperlink state.
fn osc_data_set_hyperlink_uri_updates_state() {
    let mut d = OscData::default();
    d.set_hyperlink_uri(Some("https://example.com".to_owned()));
    assert_eq!(d.hyperlink.uri.as_deref(), Some("https://example.com"));
    d.set_hyperlink_uri(None);
    assert!(d.hyperlink.uri.is_none());
}

#[test]
// MUTATION: set_pointer_shape() stores the requested cursor override.
fn osc_data_set_pointer_shape_stores_override() {
    let mut d = OscData::default();
    d.set_pointer_shape(Some("pointer".to_owned()));
    assert_eq!(d.pointer_shape.as_deref(), Some("pointer"));
    d.set_pointer_shape(None);
    assert!(d.pointer_shape.is_none());
}

#[test]
// MUTATION: Writing and reading back a palette entry must round-trip.
fn osc_data_palette_write_roundtrip() {
    let mut d = OscData::default();
    d.palette[0] = Some([0x00, 0x00, 0x00]);
    d.palette[255] = Some([0xFF, 0xFF, 0xFF]);
    assert_eq!(d.palette[0], Some([0x00, 0x00, 0x00]));
    assert_eq!(d.palette[255], Some([0xFF, 0xFF, 0xFF]));
}

#[test]
// MUTATION: Setting cwd stores the path string.
fn osc_data_set_cwd_stores_path() {
    let d = OscData {
        cwd: Some("/home/user".to_owned()),
        ..Default::default()
    };
    assert_eq!(d.cwd.as_deref(), Some("/home/user"));
}

// -------------------------------------------------------------------------
// HyperlinkState
// -------------------------------------------------------------------------

#[test]
// CONSTRUCTION: HyperlinkState::default() must have uri == None and can store a URI.
fn hyperlink_state_default_and_set_uri() {
    let mut h = HyperlinkState::default();
    assert!(h.uri.is_none());
    h.uri = Some("https://rust-lang.org".into());
    assert_eq!(h.uri.as_deref(), Some("https://rust-lang.org"));
}

// -------------------------------------------------------------------------
// PromptMark / PromptMarkEvent
// -------------------------------------------------------------------------

#[test]
// CONSTRUCTION: All four PromptMark variants are distinct.
fn prompt_mark_variants_are_distinct() {
    let variants = [
        PromptMark::PromptStart,
        PromptMark::PromptEnd,
        PromptMark::CommandStart,
        PromptMark::CommandEnd,
    ];
    for (i, a) in variants.iter().enumerate() {
        for (j, b) in variants.iter().enumerate() {
            if i == j {
                assert_eq!(a, b, "variant must equal itself");
            } else {
                assert_ne!(a, b, "variant {i} must differ from variant {j}");
            }
        }
    }
}

#[test]
// CONSTRUCTION: PromptMarkEvent fields are stored and read back correctly.
fn prompt_mark_event_fields_accessible() {
    let ev = prompt_mark_event(PromptMark::CommandEnd, 10, 3, None);
    assert!(matches!(ev.mark, PromptMark::CommandEnd));
    assert_eq!(ev.row, 10);
    assert_eq!(ev.col, 3);
    assert!(ev.exit_code.is_none());
}

// -------------------------------------------------------------------------
// ClipboardAction
// -------------------------------------------------------------------------

#[test]
// CONSTRUCTION: ClipboardAction::Write stores its payload and target.
fn clipboard_action_write_payload_stored() {
    let a = ClipboardAction::Write {
        target: SelectionTarget::Clipboard,
        data: "clipboard text".to_owned(),
    };
    assert!(matches!(a, ClipboardAction::Write { ref data, .. } if data == "clipboard text"));
}

#[test]
// CONSTRUCTION: ClipboardAction::Query is still constructible.
fn clipboard_action_query_variant() {
    let a = ClipboardAction::Query {
        target: SelectionTarget::Clipboard,
    };
    assert!(matches!(a, ClipboardAction::Query { .. }));
}

#[test]
// PARSE: empty/absent selector defaults to Clipboard.
fn selection_target_empty_defaults_clipboard() {
    assert_eq!(
        SelectionTarget::from_selector(b""),
        Some(SelectionTarget::Clipboard)
    );
}

#[test]
// PARSE: `p` selector maps to Primary.
fn selection_target_p_is_primary() {
    assert_eq!(
        SelectionTarget::from_selector(b"p"),
        Some(SelectionTarget::Primary)
    );
}

#[test]
// PARSE: `s` selector maps to Select.
fn selection_target_s_is_select() {
    assert_eq!(
        SelectionTarget::from_selector(b"s"),
        Some(SelectionTarget::Select)
    );
}

#[test]
// PARSE: q and numeric selectors are rejected.
fn selection_target_legacy_selectors_are_rejected() {
    assert_eq!(SelectionTarget::from_selector(b"q"), None);
    assert_eq!(SelectionTarget::from_selector(b"0"), None);
    assert_eq!(SelectionTarget::from_selector(b"7"), None);
}

#[test]
// PARSE: multi-character selectors are rejected.
fn selection_target_multi_char_is_rejected() {
    assert_eq!(SelectionTarget::from_selector(b"pc"), None);
}

#[test]
// PARSE: an unrecognised selector is rejected.
fn selection_target_unknown_is_rejected() {
    assert_eq!(SelectionTarget::from_selector(b"xyz"), None);
}

#[test]
// CONSTRUCTION: OscData::default() has no pending clipboard actions.
fn osc_data_default_clipboard_actions_empty() {
    let d = OscData::default();
    assert!(d.clipboard_actions.is_empty());
}

// -------------------------------------------------------------------------
// Color fields
// -------------------------------------------------------------------------

#[test]
// CONSTRUCTION: Setting default_fg via struct literal stores the color.
fn osc_data_default_fg_rgb_stored() {
    let d = osc_data_with_default_fg(Color::Rgb(255, 0, 128));
    assert!(matches!(d.default_fg, Some(Color::Rgb(255, 0, 128))));
}

#[test]
// MUTATION: Setting default_bg via struct literal stores the color.
fn osc_data_set_default_bg() {
    let d = OscData {
        default_bg: Some(Color::Rgb(255, 128, 0)),
        ..Default::default()
    };
    assert!(matches!(d.default_bg, Some(Color::Rgb(255, 128, 0))));
}

#[test]
// MUTATION: Setting cursor_color via struct literal stores the color.
fn osc_data_set_cursor_color() {
    let d = OscData {
        cursor_color: Some(Color::Default),
        ..Default::default()
    };
    assert!(matches!(d.cursor_color, Some(Color::Default)));
}

#[test]
// MUTATION: set_default_color() updates the requested slot and marks the defaults dirty.
fn osc_data_set_default_color_updates_slot_and_dirty_flag() {
    let mut d = OscData::default();
    d.set_default_color(DefaultColorSlot::Foreground, Some(Color::Rgb(1, 2, 3)));
    assert!(matches!(d.default_fg, Some(Color::Rgb(1, 2, 3))));
    assert_eq!(d.default_color_rgb(DefaultColorSlot::Foreground), [1, 2, 3]);
    assert!(d.default_colors_dirty);
}

#[test]
// MUTATION: reset_default_color() clears the requested slot and still marks defaults dirty.
fn osc_data_reset_default_color_clears_slot() {
    let mut d = OscData {
        default_bg: Some(Color::Rgb(4, 5, 6)),
        ..Default::default()
    };
    d.reset_default_color(DefaultColorSlot::Background);
    assert!(d.default_bg.is_none());
    assert!(d.default_colors_dirty);
}

#[test]
// MUTATION: mark_palette_dirty() flips the palette dirty flag without touching entries.
fn osc_data_mark_palette_dirty_sets_flag() {
    let mut d = OscData::default();
    assert!(!d.palette_dirty);
    d.mark_palette_dirty();
    assert!(d.palette_dirty);
    assert!(d.palette.iter().all(Option::is_none));
}

#[test]
// MUTATION: Prompt marks can be appended to the list.
fn osc_data_push_prompt_mark() {
    let mut d = OscData::default();
    d.prompt_marks
        .push(prompt_mark_event(PromptMark::CommandEnd, 3, 0, Some(1)));
    assert_eq!(d.prompt_marks.len(), 1);
    assert!(matches!(d.prompt_marks[0].mark, PromptMark::CommandEnd));
}

mod pbt {
    use crate::types::osc::{HyperlinkState, OscData};
    use proptest::prelude::*;
    use std::sync::Arc;

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
            let h = HyperlinkState { uri: if len == 0 { None } else { Some(Arc::from(uri.as_str())) } };
            let cloned = h.clone();
            prop_assert_eq!(cloned.uri, h.uri);
        }
    }
}
