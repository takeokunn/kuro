//! OSC event polling: CWD, clipboard, prompt marks

use emacs::defun;
use emacs::{Env, IntoLisp as _, Result as EmacsResult, Value};

use super::{
    build_emacs_list_from_rev, build_emacs_list_from_values, define_session_data_query_mut,
    define_session_data_query_or_false, define_session_query_bool, define_session_query_default,
    define_session_query_opt, query_session, query_session_mut, query_session_opt,
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
// Returns a list of clipboard actions. Each action is a 3-element list whose
// first element is the action tag, second the payload, and third the selection
// target string ("clipboard", "primary", or "select"):
//   - ("write" TEXT TARGET) for a write action
//   - ("query" nil  TARGET) for a query action
// The TARGET lets Emacs route OSC 52 ; p to PRIMARY vs ; c to CLIPBOARD.
define_drain_session_vec_to_lisp!(
    kuro_core_poll_clipboard_actions,
    "poll_clipboard_actions",
    super::super::abstraction::session::TerminalSession::take_clipboard_actions,
    |env, action| {
        let item = match action {
            crate::types::osc::ClipboardAction::Write { target, data } => {
                let tag = "write".into_lisp(env)?;
                let text_val = data.into_lisp(env)?;
                let target_val = selection_target_name(target).into_lisp(env)?;
                build_emacs_list_from_values(env, [tag, text_val, target_val])?
            }
            crate::types::osc::ClipboardAction::Query { target } => {
                let tag = "query".into_lisp(env)?;
                let target_val = selection_target_name(target).into_lisp(env)?;
                build_emacs_list_from_values(env, [tag, false.into_lisp(env)?, target_val])?
            }
        };
        Ok(item)
    }
);

define_session_query_bool!(
    /// Enqueue an OSC 99 desktop-notification action response back to the PTY.
    ///
    /// Called by Emacs when the user acts on a notification that requested an
    /// `a=report` action. `id` is the notification id echoed back; `button` is a
    /// 0-based button index, or any negative value for plain activation (no
    /// button); `close` is non-zero for the `p=close` close-report variant.
    ///
    /// The response (`OSC 99 ; i=<id> ; <button> ST`, or the close variant) is
    /// pushed onto pending responses and flushed to the PTY on the next poll,
    /// exactly like a DSR/DA reply. Returns t on success, nil if the session is
    /// missing.
    kuro_core_notify_action_response,
    |id: String, button: i64, close: i64| query_session_mut,
    |session| {
        let btn = if button < 0 {
            None
        } else {
            Some(button as u32)
        };
        session.notify_action_response(&id, btn, close != 0);
        Ok(true)
    }
);

/// Map a [`SelectionTarget`] to the stable string Emacs uses to route the
/// clipboard write/query to the correct selection.
#[inline]
fn selection_target_name(target: crate::types::osc::SelectionTarget) -> String {
    use crate::types::osc::SelectionTarget;
    match target {
        SelectionTarget::Clipboard => "clipboard".to_owned(),
        SelectionTarget::Primary => "primary".to_owned(),
        SelectionTarget::Select => "select".to_owned(),
    }
}

// Poll for pending desktop notifications (OSC 9 / OSC 777 / OSC 99) and clear them.
//
// Returns a list of `(TITLE BODY ID REPORT)` 4-element lists, where:
//   - TITLE is the notification title string (OSC 777 / OSC 99 p=title) or nil
//     (the iTerm2 OSC 9 form and OSC 99 without a title).
//   - BODY is the notification body string.
//   - ID is the OSC 99 `i=<id>` notification id string, or nil for OSC 9 / 777
//     and OSC 99 without an `i=` field.  The id is echoed in any action response.
//   - REPORT is t when the OSC 99 metadata requested an `a=report` activation
//     report (so Emacs should wire :actions / :on-action), nil otherwise.
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
        let id = match notif.id {
            Some(i) => i.into_lisp(env)?,
            None => false.into_lisp(env)?,
        };
        let report = notif.report.into_lisp(env)?;
        build_emacs_list_from_values(env, [title, body, id, report])
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
        let row_val = (event.row as i64).into_lisp(env)?;
        let col_val = (event.col as i64).into_lisp(env)?;
        let exit_val = match event.exit_code {
            Some(code) => i64::from(code).into_lisp(env)?,
            None => false.into_lisp(env)?,
        };
        let aid_val = match event.aid {
            Some(s) => s.into_lisp(env)?,
            None => false.into_lisp(env)?,
        };
        let duration_val = match event.duration_ms {
            Some(ms) => (ms as i64).into_lisp(env)?,
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

// Poll for pending OSC 51 command payloads and clear them.
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
    #[expect(
        clippy::cast_possible_wrap,
        reason = "row/start/end are terminal dimensions (≤ 65535); usize→i64 never wraps"
    )]
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
            let row_val = (row as i64).into_lisp(env)?;
            let start_val = (start as i64).into_lisp(env)?;
            let end_val = (end as i64).into_lisp(env)?;
            let uri_val = uri.into_lisp(env)?;

            build_emacs_list_from_values(env, [row_val, start_val, end_val, uri_val])
        })
    }
);

define_session_data_query_or_false!(
    #[expect(
        clippy::cast_possible_wrap,
        reason = "row/start/end are terminal dimensions (≤ 65535); usize→i64 never wraps"
    )]
    /// Poll Kitty text-sizing (OSC 66) ranges for all visible terminal rows.
    ///
    /// Returns a flat list of `(ROW START END SCALED-PERMILLE)` entries, one per
    /// text-size range per row.  `START` and `END` are buffer character offsets;
    /// `SCALED-PERMILLE` is the effective size multiplier ×1000 (e.g. `2000` =
    /// 2× size, `500` = half size).  Rows without any sized cells are omitted.
    kuro_core_poll_text_size_ranges,
    "poll_text_size_ranges",
    |session| session.get_text_size_ranges(),
    |kuro_env, ranges| {
        build_emacs_list_from_rev(kuro_env, ranges, |env, (row, start, end, permille)| {
            let row_val = (row as i64).into_lisp(env)?;
            let start_val = (start as i64).into_lisp(env)?;
            let end_val = (end as i64).into_lisp(env)?;
            let permille_val = i64::from(permille).into_lisp(env)?;

            build_emacs_list_from_values(env, [row_val, start_val, end_val, permille_val])
        })
    }
);

define_session_data_query_mut!(
    /// Get the iTerm2 OSC 1337 `RemoteHost=<user@host>` value if it changed.
    ///
    /// Returns the remote-host string when it has been updated since the last
    /// call (clearing the dirty flag), or nil otherwise.
    kuro_core_get_remote_host,
    "get_remote_host",
    |session| session.take_remote_host_if_dirty(),
    |env, result| match result {
        Some(host) => host.into_lisp(env),
        None => false.into_lisp(env),
    },
    |env| false.into_lisp(env)
);

define_session_data_query_mut!(
    /// Poll iTerm2 OSC 1337 `SetUserVar` user variables if they changed.
    ///
    /// Returns a list of `(NAME . VALUE)` cons cells (the full current set) when
    /// the user-vars changed since the last call (clearing the dirty flag), or
    /// nil when unchanged. `VALUE` is the base64-decoded user-variable value.
    kuro_core_poll_user_vars,
    "poll_user_vars",
    |session| session.take_user_vars_if_dirty(),
    |env, result| match result {
        Some(vars) => {
            let mut values = Vec::with_capacity(vars.len());
            for (name, value) in vars {
                let name_val = name.into_lisp(env)?;
                let value_val = value.into_lisp(env)?;
                values.push(env.cons(name_val, value_val)?);
            }
            build_emacs_list_from_values(env, values)
        }
        None => false.into_lisp(env),
    },
    |env| false.into_lisp(env)
);

define_session_data_query_mut!(
    /// Get the ConEmu OSC 9;4 progress state if it changed.
    ///
    /// Returns a `(STATE . PERCENT)` cons cell when the progress state changed
    /// since the last call (clearing the dirty flag), or nil when unchanged.
    /// STATE is 0=none, 1=set, 2=error, 3=indeterminate, 4=warning; PERCENT is
    /// 0–100 (0 for the stateless none/indeterminate variants).
    kuro_core_get_progress,
    "get_progress",
    |session| session.take_progress_if_dirty(),
    |env, result| match result {
        Some((state, percent)) => {
            let state_val = i64::from(state).into_lisp(env)?;
            let percent_val = i64::from(percent).into_lisp(env)?;
            env.cons(state_val, percent_val)
        }
        None => false.into_lisp(env),
    },
    |env| false.into_lisp(env)
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
