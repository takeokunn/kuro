//! OSC event polling: CWD, clipboard, prompt marks

use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

use super::{
    build_emacs_list_from_rev, build_emacs_list_from_values, define_session_data_query_mut,
    define_session_data_query_or_false, define_session_query_default, define_session_query_opt,
    query_session, query_session_opt, u64_to_lisp_i64, usize_to_lisp_i64,
};

define_session_query_opt!(
    /// Get the current working directory from OSC 7 and atomically clear the dirty flag.
    ///
    /// Returns the CWD path string if one has been set since the last call,
    /// or nil if no CWD update is pending.
    kuro_core_get_cwd,
    query_session_opt,
    |session| session.take_cwd_if_dirty()
);

// Poll for pending clipboard actions from OSC 52 and clear them.
//
// Returns a list of clipboard actions. Each action is either:
//   - ("write" . TEXT) for a write action
//   - ("query" . nil) for a query action
define_drain_session_vec_to_lisp!(
    kuro_core_poll_clipboard_actions,
    "poll_clipboard_actions",
    super::super::abstraction::session::TerminalSession::take_clipboard_actions,
    |env, action| {
        let item = match action {
            crate::types::osc::ClipboardAction::Write(text) => {
                let tag = "write".into_lisp(env)?;
                let text_val = text.into_lisp(env)?;
                build_emacs_list_from_values(env, [tag, text_val])?
            }
            crate::types::osc::ClipboardAction::Query => {
                let tag = "query".into_lisp(env)?;
                build_emacs_list_from_values(env, [tag, false.into_lisp(env)?])?
            }
        };
        Ok(item)
    }
);

// Poll for pending desktop notifications (OSC 9 / OSC 777) and clear them.
//
// Returns a list of `(TITLE . BODY)` cons cells, where TITLE is the
// notification title string (OSC 777) or nil (the iTerm2 OSC 9 form), and
// BODY is the notification body string.
define_drain_session_vec_to_lisp!(
    kuro_core_poll_notifications,
    "poll_notifications",
    super::super::abstraction::session::TerminalSession::take_notifications,
    |env, notif| {
        let nil = false.into_lisp(env)?;
        let title = match notif.title {
            Some(t) => t.into_lisp(env)?,
            None => nil,
        };
        let body = notif.body.into_lisp(env)?;
        build_emacs_list_from_values(env, [title, body])
    }
);

// Poll for pending prompt mark events from OSC 133 and clear them.
//
// Returns a list of prompt mark descriptors, each of the form:
//   (MARK-TYPE ROW COL EXIT-CODE AID DURATION-MS ERR-PATH)
// where:
//   - MARK-TYPE is one of: "prompt-start", "prompt-end", "command-start", "command-end".
//   - EXIT-CODE is an integer for command-end marks or nil for others.
//   - AID is the application id string (OSC 133 `aid=` kv, Ghostty 1.3+) or nil.
//     An explicit empty `aid=""` is preserved as the empty string and is NOT
//     converted to nil.
//   - DURATION-MS is the command duration in milliseconds (OSC 133 D `duration=`
//     kv, Ghostty 1.3+) as an integer, or nil when absent.
//   - ERR-PATH is the stderr log path (OSC 133 D `err=` kv, FinalTerm/Ghostty)
//     as a string, or nil when absent.
//
// See: <https://gitlab.freedesktop.org/Per_Bothner/specifications/-/blob/master/proposals/semantic-prompts.md>
define_drain_session_vec_to_lisp!(
    kuro_core_poll_prompt_marks,
    "poll_prompt_marks",
    super::super::abstraction::session::TerminalSession::take_prompt_marks,
    |env, event| {
        let mark_str = match event.mark {
            crate::types::osc::PromptMark::PromptStart => "prompt-start",
            crate::types::osc::PromptMark::PromptEnd => "prompt-end",
            crate::types::osc::PromptMark::CommandStart => "command-start",
            crate::types::osc::PromptMark::CommandEnd => "command-end",
        };
        let mark_val = mark_str.into_lisp(env)?;
        let row_val =
            usize_to_lisp_i64(event.row, "prompt mark row must fit i64").into_lisp(env)?;
        let col_val =
            usize_to_lisp_i64(event.col, "prompt mark column must fit i64").into_lisp(env)?;
        let exit_val = match event.exit_code {
            Some(code) => i64::from(code).into_lisp(env)?,
            None => false.into_lisp(env)?,
        };
        let aid_val = match event.aid {
            Some(s) => s.into_lisp(env)?,
            None => false.into_lisp(env)?,
        };
        let duration_val = match event.duration_ms {
            Some(ms) => u64_to_lisp_i64(ms, "prompt mark duration must fit i64").into_lisp(env)?,
            None => false.into_lisp(env)?,
        };
        let err_val = match event.err_path {
            Some(s) => s.into_lisp(env)?,
            None => false.into_lisp(env)?,
        };

        build_emacs_list_from_values(
            env,
            [
                mark_val,
                row_val,
                col_val,
                exit_val,
                aid_val,
                duration_val,
                err_val,
            ],
        )
    }
);

// Poll for pending OSC 51 eval commands and clear them.
// Returns a list of command strings.
define_drain_session_vec_to_lisp!(
    kuro_core_poll_eval_commands,
    "poll_eval_commands",
    super::super::abstraction::session::TerminalSession::take_eval_commands,
    |env, cmd| { cmd.into_lisp(env) }
);

define_session_query_opt!(
    /// Get the hostname from the last OSC 7 notification.
    /// Returns the hostname string or nil if localhost/unset.
    kuro_core_get_cwd_host,
    query_session_opt,
    |session| session.get_cwd_host()
);

define_session_query_default!(
    /// Check if the PTY has pending unread output (non-blocking).
    ///
    /// Returns t if the PTY channel has data waiting to be rendered,
    /// nil otherwise.  Used by Emacs to trigger immediate render cycles
    /// for low-latency streaming output (AI agents, etc.).
    kuro_core_has_pending_output,
    false,
    query_session,
    |session| session.has_pending_output()
);

define_session_query_default!(
    /// Check if the PTY child process is still running.
    ///
    /// Returns t if the shell process has not yet exited, nil if it has.
    /// Used by Emacs to automatically kill the terminal buffer when the
    /// process exits (e.g., user types `exit').
    /// Returns nil (process gone) when no session is active.
    kuro_core_is_process_alive,
    false,
    query_session,
    |session| session.is_process_alive()
);

define_session_data_query_or_false!(
    /// Get palette overrides from OSC 4 as a list of (index r g b) entries.
    ///
    /// Returns a list of (INDEX R G B) for each palette entry overridden via OSC 4.
    /// Only returns non-default (overridden) entries.
    kuro_core_get_palette_updates,
        "get_palette_updates",
        |session| session.get_palette_updates(),
        |kuro_env, updates| {
            build_emacs_list_from_rev(kuro_env, updates, |env, (idx, r, g, b)| {
                let idx_val = i64::from(idx).into_lisp(env)?;
                let r_val = i64::from(r).into_lisp(env)?;
                let g_val = i64::from(g).into_lisp(env)?;
                let b_val = i64::from(b).into_lisp(env)?;

                build_emacs_list_from_values(env, [idx_val, r_val, g_val, b_val])
            })
        }
);

define_session_data_query_or_false!(
    /// Poll hyperlink ranges for all visible terminal rows.
    ///
    /// Returns a flat list of `(ROW START END URI)` entries, one per hyperlink
    /// range per row.  `START` and `END` are buffer character offsets.
    /// Rows without hyperlinks are omitted.
    kuro_core_poll_hyperlink_ranges,
    "poll_hyperlink_ranges",
    |session| session.get_hyperlink_ranges(),
    |kuro_env, ranges| {
        build_emacs_list_from_rev(kuro_env, ranges, |env, (row, start, end, uri)| {
            let row_val = usize_to_lisp_i64(row, "hyperlink row must fit i64").into_lisp(env)?;
            let start_val =
                usize_to_lisp_i64(start, "hyperlink start must fit i64").into_lisp(env)?;
            let end_val = usize_to_lisp_i64(end, "hyperlink end must fit i64").into_lisp(env)?;
            let uri_val = uri.into_lisp(env)?;

            build_emacs_list_from_values(env, [row_val, start_val, end_val, uri_val])
        })
    }
);

define_session_data_query_mut!(
    /// Get default terminal colors (OSC 10/11/12) as encoded u32 values.
    ///
    /// Returns a cons cell (FG-ENC . (BG-ENC . CURSOR-ENC)) where each value is
    /// a u32 FFI color encoding (0xFF000000 = default/unset).
    /// Also clears the dirty flag atomically.
    kuro_core_get_default_colors,
    "get_default_colors",
    |session| session.take_default_colors_dirty().then(|| session.get_default_colors()),
    |env, result| match result {
        Some((fg, bg, cur)) => {
            let fg_val = i64::from(fg).into_lisp(env)?;
            let bg_val = i64::from(bg).into_lisp(env)?;
            let cur_val = i64::from(cur).into_lisp(env)?;
            build_emacs_list_from_values(env, [fg_val, bg_val, cur_val, false.into_lisp(env)?])
        }
        None => false.into_lisp(env),
    },
    |env| false.into_lisp(env)
);
