//! OSC (Operating System Command) data types

use std::sync::Arc;

use crate::types::color::Color;

/// Prompt mark type for OSC 133 shell integration
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PromptMark {
    /// A - Prompt start
    PromptStart,
    /// B - Prompt end
    PromptEnd,
    /// C - Command start
    CommandStart,
    /// D - Command end
    CommandEnd,
}

/// Pending prompt mark with position
#[derive(Debug, Clone)]
pub struct PromptMarkEvent {
    /// The mark type
    pub(crate) mark: PromptMark,
    /// Row position when mark was received
    pub(crate) row: usize,
    /// Column position when mark was received
    pub(crate) col: usize,
    /// Exit code from OSC 133;D (None for A/B/C marks)
    pub(crate) exit_code: Option<i32>,
}

/// Active hyperlink state for OSC 8
#[derive(Debug, Clone, Default)]
pub struct HyperlinkState {
    /// The URI of the hyperlink, or None if no hyperlink is active
    /// NOTE: kept pub for integration test access (tests/ crate)
    pub uri: Option<Arc<str>>,
}

/// Clipboard action for OSC 52
#[derive(Debug, Clone)]
pub enum ClipboardAction {
    /// Write text to clipboard
    Write(String),
    /// Query clipboard contents
    Query,
}

/// OSC data storage
#[derive(Debug)]
pub struct OscData {
    /// Current working directory from OSC 7
    pub cwd: Option<String>,
    /// Whether cwd has been updated and not yet read
    pub cwd_dirty: bool,
    /// Active hyperlink state from OSC 8
    pub hyperlink: HyperlinkState,
    /// Pending clipboard actions from OSC 52
    pub(crate) clipboard_actions: Vec<ClipboardAction>,
    /// Pending prompt mark events from OSC 133
    pub prompt_marks: Vec<PromptMarkEvent>,
    /// Whether the color palette needs to be reset (OSC 104)
    pub(crate) palette_dirty: bool,
    /// Default foreground color from OSC 10
    pub default_fg: Option<Color>,
    /// Default background color from OSC 11
    pub default_bg: Option<Color>,
    /// Cursor color from OSC 12
    pub cursor_color: Option<Color>, // NOTE: kept pub for integration test access (tests/ crate)
    /// 256-color palette overrides from OSC 4 (index → `[R,G,B]` or `None`=unset)
    pub palette: Vec<Option<[u8; 3]>>,
    /// Pending default-color-change notifications for FFI (fg, bg, cursor)
    pub(crate) default_colors_dirty: bool,
    /// Pending Elisp eval commands from OSC 51 (security: whitelist-filtered on Elisp side)
    pub(crate) eval_commands: Vec<String>,
    /// Hostname from OSC 7 (None = localhost)
    pub(crate) cwd_host: Option<String>,
}

impl Default for OscData {
    fn default() -> Self {
        Self {
            cwd: None,
            cwd_dirty: false,
            hyperlink: HyperlinkState::default(),
            clipboard_actions: Vec::new(),
            prompt_marks: Vec::new(),
            palette_dirty: false,
            default_fg: None,
            default_bg: None,
            cursor_color: None,
            palette: vec![None; 256],
            default_colors_dirty: false,
            eval_commands: Vec::new(),
            cwd_host: None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::color::Color;

    // -------------------------------------------------------------------------
    // OscData construction
    // -------------------------------------------------------------------------

    #[test]
    // CONSTRUCTION: OscData::default() must initialise cwd_dirty to false.
    fn osc_data_default_cwd_dirty_false() {
        assert!(!OscData::default().cwd_dirty);
    }

    #[test]
    // CONSTRUCTION: OscData::default() palette must have exactly 256 None entries.
    fn osc_data_default_palette_len_256_all_none() {
        let d = OscData::default();
        assert_eq!(d.palette.len(), 256);
        assert!(d.palette.iter().all(Option::is_none));
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
    // CONSTRUCTION: HyperlinkState::default() must have uri == None.
    fn hyperlink_state_default_is_none() {
        assert!(HyperlinkState::default().uri.is_none());
    }

    #[test]
    // MUTATION: Setting uri to Some and back to None round-trips.
    fn hyperlink_state_set_then_clear_uri() {
        let mut h = HyperlinkState {
            uri: Some(Arc::from("https://rust-lang.org")),
        };
        assert_eq!(h.uri.as_deref(), Some("https://rust-lang.org"));
        h.uri = None;
        assert!(h.uri.is_none());
    }

    // -------------------------------------------------------------------------
    // PromptMark / PromptMarkEvent
    // -------------------------------------------------------------------------

    #[test]
    // CONSTRUCTION: All four PromptMark variants are distinct.
    fn prompt_mark_all_variants_distinct() {
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
    fn prompt_mark_event_field_access() {
        let ev = PromptMarkEvent {
            mark: PromptMark::CommandEnd,
            row: 10,
            col: 3,
            exit_code: None,
        };
        assert!(matches!(ev.mark, PromptMark::CommandEnd));
        assert_eq!(ev.row, 10);
        assert_eq!(ev.col, 3);
        assert!(ev.exit_code.is_none());
    }

    // -------------------------------------------------------------------------
    // ClipboardAction
    // -------------------------------------------------------------------------

    #[test]
    // CONSTRUCTION: ClipboardAction::Write stores its payload.
    fn clipboard_action_write_payload_stored() {
        let a = ClipboardAction::Write("clipboard text".to_owned());
        assert!(matches!(a, ClipboardAction::Write(ref s) if s == "clipboard text"));
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
        let d = OscData {
            default_fg: Some(Color::Rgb(255, 0, 128)),
            ..Default::default()
        };
        assert!(matches!(d.default_fg, Some(Color::Rgb(255, 0, 128))));
    }
}
