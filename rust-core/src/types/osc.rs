//! OSC (Operating System Command) data types

use crate::types::color::Color;

/// Prompt mark type for OSC 133 shell integration
#[derive(Debug, Clone, PartialEq)]
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
    pub mark: PromptMark,
    /// Row position when mark was received
    pub row: usize,
    /// Column position when mark was received
    pub col: usize,
}

/// Active hyperlink state for OSC 8
#[derive(Debug, Clone, Default)]
pub struct HyperlinkState {
    /// The URI of the hyperlink, or None if no hyperlink is active
    pub uri: Option<String>,
    /// Optional id parameter from the hyperlink params
    pub id: Option<String>,
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
    pub clipboard_actions: Vec<ClipboardAction>,
    /// Pending prompt mark events from OSC 133
    pub prompt_marks: Vec<PromptMarkEvent>,
    /// Whether the color palette needs to be reset (OSC 104)
    pub palette_dirty: bool,
    /// Default foreground color from OSC 10
    pub default_fg: Option<Color>,
    /// Default background color from OSC 11
    pub default_bg: Option<Color>,
    /// Cursor color from OSC 12
    pub cursor_color: Option<Color>,
    /// 256-color palette overrides from OSC 4 (index → [R,G,B] or None=unset)
    pub palette: Vec<Option<[u8; 3]>>,
    /// Pending default-color-change notifications for FFI (fg, bg, cursor)
    pub default_colors_dirty: bool,
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
        }
    }
}
