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
#[cfg_attr(
    fuzzing,
    expect(
        dead_code,
        reason = "fields read only by ffi::bridge which is excluded in fuzz builds"
    )
)]
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
    /// Application id (OSC 133 aid= param, Ghostty 1.3+).
    pub(crate) aid: Option<String>,
    /// Command duration in milliseconds (OSC 133 D duration= param, Ghostty 1.3+).
    pub(crate) duration_ms: Option<u64>,
    /// Stderr log path (OSC 133 D err= param, FinalTerm/Ghostty).
    pub(crate) err_path: Option<String>,
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

/// Desktop notification request from OSC 9 (iTerm2) or OSC 777 (`notify`).
#[derive(Debug, Clone)]
pub struct Notification {
    /// Optional title — OSC 777 supplies one; the iTerm2 OSC 9 form does not.
    pub title: Option<String>,
    /// Notification body text.
    pub body: String,
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
    /// Pending desktop notifications from OSC 9 (iTerm2) / OSC 777
    pub(crate) notifications: Vec<Notification>,
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
    /// Window pointer cursor shape from OSC 22 (e.g. "default", "pointer", "text").
    /// None = no override set; Some(name) = application-requested cursor name.
    pub(crate) pointer_shape: Option<String>,
    /// Save/restore stack for the 256-color palette (XTPUSHCOLORS / XTPOPCOLORS).
    /// CSI # P pushes; CSI # Q pops and restores palette_dirty; capped at 10.
    pub(crate) palette_stack: Vec<Vec<Option<[u8; 3]>>>,
}

impl Default for OscData {
    fn default() -> Self {
        Self {
            cwd: None,
            cwd_dirty: false,
            hyperlink: HyperlinkState::default(),
            clipboard_actions: Vec::new(),
            notifications: Vec::new(),
            prompt_marks: Vec::new(),
            palette_dirty: false,
            default_fg: None,
            default_bg: None,
            cursor_color: None,
            palette: vec![None; 256],
            default_colors_dirty: false,
            eval_commands: Vec::new(),
            cwd_host: None,
            pointer_shape: None,
            palette_stack: Vec::new(),
        }
    }
}


#[cfg(test)]
mod tests {
    include!("osc_tests.rs");
}
