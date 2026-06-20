//! OSC (Operating System Command) data types

use std::sync::Arc;

use crate::types::color::Color;

/// Default color slots handled by OSC 10/11/12 and resets 110/111/112.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum DefaultColorSlot {
    Foreground,
    Background,
    Cursor,
}

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

impl PromptMark {
    /// Maps an OSC 133 mark byte to a prompt mark variant.
    pub(crate) fn from_osc_133_mark(mark: u8) -> Option<Self> {
        match mark {
            b'A' => Some(Self::PromptStart),
            b'B' => Some(Self::PromptEnd),
            b'C' => Some(Self::CommandStart),
            b'D' => Some(Self::CommandEnd),
            _ => None,
        }
    }
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

impl PromptMarkEvent {
    /// Creates a prompt-mark event from the parsed OSC 133 payload and cursor position.
    pub(crate) fn new(
        mark: PromptMark,
        row: usize,
        col: usize,
        exit_code: Option<i32>,
        aid: Option<String>,
        duration_ms: Option<u64>,
        err_path: Option<String>,
    ) -> Self {
        Self {
            mark,
            row,
            col,
            exit_code,
            aid,
            duration_ms,
            err_path,
        }
    }
}

/// Active hyperlink state for OSC 8
#[derive(Debug, Clone, Default)]
pub struct HyperlinkState {
    /// The URI of the hyperlink, or None if no hyperlink is active
    pub(crate) uri: Option<Arc<str>>,
}

/// Selection target for an OSC 52 clipboard operation.
///
/// Carries the `Pc` selector parsed from `OSC 52 ; Pc ; Pd ST`. The wire
/// selector is a string of chars from `{c,p,q,s,0-7}`; the first recognised
/// char wins and an empty/absent selector defaults to [`SelectionTarget::Clipboard`]
/// per the xterm convention.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SelectionTarget {
    /// `c` — system clipboard (CLIPBOARD).
    Clipboard,
    /// `p` — primary selection (PRIMARY).
    Primary,
    /// `s` — select / secondary (mapped to xterm's "select" buffer).
    Select,
    /// `0`-`7` — numbered cut buffers.
    CutBuffer(u8),
}

impl SelectionTarget {
    /// Parse the OSC 52 `Pc` selector field. The first recognised selector
    /// char determines the target; an empty selector (or one with no
    /// recognised char) defaults to [`SelectionTarget::Clipboard`].
    pub(crate) fn from_selector(sel: &[u8]) -> Self {
        for &b in sel {
            match b {
                b'c' => return Self::Clipboard,
                b'p' => return Self::Primary,
                b's' | b'q' => return Self::Select,
                b'0'..=b'7' => return Self::CutBuffer(b - b'0'),
                _ => {}
            }
        }
        Self::Clipboard
    }
}

/// Clipboard action for OSC 52
#[derive(Debug, Clone)]
pub enum ClipboardAction {
    /// Write text to the given selection target.
    Write {
        /// Selection target parsed from the OSC 52 `Pc` field.
        target: SelectionTarget,
        /// The decoded clipboard text.
        data: String,
    },
    /// Query the contents of the given selection target.
    Query {
        /// Selection target parsed from the OSC 52 `Pc` field.
        target: SelectionTarget,
    },
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
    pub(crate) cwd: Option<String>,
    /// Whether cwd has been updated and not yet read
    pub(crate) cwd_dirty: bool,
    /// Active hyperlink state from OSC 8
    pub(crate) hyperlink: HyperlinkState,
    /// Pending clipboard actions from OSC 52
    pub(crate) clipboard_actions: Vec<ClipboardAction>,
    /// Pending desktop notifications from OSC 9 (iTerm2) / OSC 777
    pub(crate) notifications: Vec<Notification>,
    /// Pending prompt mark events from OSC 133
    pub(crate) prompt_marks: Vec<PromptMarkEvent>,
    /// Whether the color palette needs to be reset (OSC 104)
    pub(crate) palette_dirty: bool,
    /// Default foreground color from OSC 10
    pub(crate) default_fg: Option<Color>,
    /// Default background color from OSC 11
    pub(crate) default_bg: Option<Color>,
    /// Cursor color from OSC 12
    pub(crate) cursor_color: Option<Color>,
    /// 256-color palette overrides from OSC 4 (index → `[R,G,B]` or `None`=unset)
    pub(crate) palette: Vec<Option<[u8; 3]>>,
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
    /// In-progress OSC 99 (Kitty notification) chunk keyed by the `i=<id>` field.
    /// `d=0` chunks accumulate here; `d=1` finalizes and pushes to `notifications`.
    pub(crate) notification_chunk: Option<NotificationChunk>,
}

/// Accumulator for a chunked OSC 99 (Kitty desktop notification).
///
/// Kitty allows a notification to be sent in multiple `OSC 99` sequences sharing
/// the same `i=<id>`; intermediate chunks set `d=0` (done=false) and the final
/// chunk sets `d=1`. Title and body payloads accumulate independently here until
/// the notification is finalized and pushed to [`OscData::notifications`].
#[derive(Debug, Clone, Default)]
pub(crate) struct NotificationChunk {
    /// The `i=<id>` value that groups chunks of the same notification.
    pub(crate) id: String,
    /// Accumulated `p=title` payload bytes.
    pub(crate) title: String,
    /// Accumulated `p=body` payload bytes.
    pub(crate) body: String,
}

impl OscData {
    /// Returns the current working directory reported by OSC 7.
    pub fn cwd(&self) -> Option<&str> {
        self.cwd.as_deref()
    }

    /// Returns whether the current working directory has changed and is unread.
    pub fn cwd_dirty(&self) -> bool {
        self.cwd_dirty
    }

    /// Returns the active OSC 8 hyperlink URI.
    pub fn hyperlink_uri(&self) -> Option<&str> {
        self.hyperlink.uri.as_deref()
    }

    /// Sets the active OSC 8 hyperlink URI.
    pub(crate) fn set_hyperlink_uri(&mut self, uri: Option<String>) {
        self.hyperlink.uri = uri.map(Arc::from);
    }

    /// Returns the pending OSC 133 prompt marks.
    pub fn prompt_marks(&self) -> &[PromptMarkEvent] {
        &self.prompt_marks
    }

    /// Returns the current OSC 10 default foreground color.
    pub fn default_fg(&self) -> Option<Color> {
        self.default_fg
    }

    /// Returns the current OSC 11 default background color.
    pub fn default_bg(&self) -> Option<Color> {
        self.default_bg
    }

    /// Returns the current OSC 12 cursor color.
    pub fn cursor_color(&self) -> Option<Color> {
        self.cursor_color
    }

    /// Returns the OSC 4 palette overrides.
    pub fn palette(&self) -> &[Option<[u8; 3]>] {
        &self.palette
    }

    /// Stores the OSC 7 current working directory and hostname and marks the value dirty.
    pub(crate) fn set_cwd(&mut self, cwd_host: Option<String>, cwd: Option<String>) {
        self.cwd_host = cwd_host;
        self.cwd = cwd;
        self.cwd_dirty = true;
    }

    /// Stores the OSC 22 pointer shape override.
    pub(crate) fn set_pointer_shape(&mut self, pointer_shape: Option<String>) {
        self.pointer_shape = pointer_shape;
    }

    /// Resets the entire OSC 4 palette and marks it dirty.
    pub(crate) fn clear_palette(&mut self) {
        for entry in &mut self.palette {
            *entry = None;
        }
        self.palette_dirty = true;
    }

    /// Resets one OSC 4 palette entry and marks the palette dirty.
    pub(crate) fn clear_palette_entry(&mut self, idx: usize) {
        if let Some(entry) = self.palette.get_mut(idx) {
            *entry = None;
            self.palette_dirty = true;
        }
    }

    /// Stores one OSC 4 palette entry and marks the palette dirty.
    pub(crate) fn set_palette_entry(&mut self, idx: usize, color: [u8; 3]) {
        if let Some(entry) = self.palette.get_mut(idx) {
            *entry = Some(color);
            self.palette_dirty = true;
        }
    }

    /// Restores the full OSC 4 palette from a saved snapshot and marks it dirty.
    pub(crate) fn restore_palette(&mut self, palette: Vec<Option<[u8; 3]>>) {
        self.palette = palette;
        self.palette_dirty = true;
    }

    /// Marks the OSC 4 palette as dirty for FFI/render consumers.
    pub(crate) fn mark_palette_dirty(&mut self) {
        self.palette_dirty = true;
    }

    pub(crate) fn default_color(&self, slot: DefaultColorSlot) -> &Option<Color> {
        match slot {
            DefaultColorSlot::Foreground => &self.default_fg,
            DefaultColorSlot::Background => &self.default_bg,
            DefaultColorSlot::Cursor => &self.cursor_color,
        }
    }

    pub(crate) fn set_default_color(&mut self, slot: DefaultColorSlot, color: Option<Color>) {
        match slot {
            DefaultColorSlot::Foreground => self.default_fg = color,
            DefaultColorSlot::Background => self.default_bg = color,
            DefaultColorSlot::Cursor => self.cursor_color = color,
        }
        self.default_colors_dirty = true;
    }

    pub(crate) fn reset_default_color(&mut self, slot: DefaultColorSlot) {
        self.set_default_color(slot, None);
    }

    pub(crate) fn default_color_rgb(&self, slot: DefaultColorSlot) -> [u8; 3] {
        match self.default_color(slot) {
            Some(Color::Rgb(r, g, b)) => [*r, *g, *b],
            _ => [128, 128, 128],
        }
    }

    /// Pushes an OSC 133 prompt mark if the queue has not reached `max_pending`.
    pub(crate) fn push_prompt_mark(&mut self, event: PromptMarkEvent, max_pending: usize) -> bool {
        if self.prompt_marks.len() >= max_pending {
            return false;
        }
        self.prompt_marks.push(event);
        true
    }
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
            notification_chunk: None,
        }
    }
}

#[cfg(test)]
#[path = "osc/tests.rs"]
mod tests;
