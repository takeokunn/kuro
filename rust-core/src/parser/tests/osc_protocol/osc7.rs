use crate::TerminalCore;

// ── handle_osc_7 hostname preservation ───────────────────────────────────────

#[test]
fn osc7_localhost_yields_none_host() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"7", b"file://localhost/home/user"];
    crate::parser::osc::handle_osc(&mut core, params, false);
    assert_eq!(core.osc_data().cwd.as_deref(), Some("/home/user"));
    assert!(core.osc_data().cwd_host.is_none());
}

#[test]
fn osc7_empty_host_yields_none() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"7", b"file:///tmp"];
    crate::parser::osc::handle_osc(&mut core, params, false);
    assert_eq!(core.osc_data().cwd.as_deref(), Some("/tmp"));
    assert!(core.osc_data().cwd_host.is_none());
}

#[test]
fn osc7_remote_host_preserved() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    let params: &[&[u8]] = &[b"7", b"file://myhost/home/user"];
    crate::parser::osc::handle_osc(&mut core, params, false);
    assert_eq!(core.osc_data().cwd.as_deref(), Some("/home/user"));
    assert_eq!(core.osc_data().cwd_host.as_deref(), Some("myhost"));
}

#[test]
fn osc7_host_cleared_on_localhost() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    // First set a remote host
    let params: &[&[u8]] = &[b"7", b"file://remotehost/srv"];
    crate::parser::osc::handle_osc(&mut core, params, false);
    assert_eq!(core.osc_data().cwd_host.as_deref(), Some("remotehost"));
    // Then set localhost — host should be cleared
    let params2: &[&[u8]] = &[b"7", b"file://localhost/home"];
    crate::parser::osc::handle_osc(&mut core, params2, false);
    assert!(core.osc_data().cwd_host.is_none());
    assert_eq!(core.osc_data().cwd.as_deref(), Some("/home"));
}

// ── DA3 ordering / Mode 2031 default state (FR-115 / FR-117) ─────────────────

/// DA3 (`CSI = c`) issued after DA1 (`CSI c`) queues responses in submission
/// order — DA1 response first, DA3 response second.
#[test]
fn da1_then_da3_responses_in_submission_order() {
    use crate::TerminalCore;
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b[c\x1b[=c");
    let responses = core.pending_responses();
    assert_eq!(
        responses.len(),
        2,
        "both DA1 and DA3 must enqueue a response"
    );
    // DA1 response: CSI ? 1 ; 2 ; 4 c (VT100 + advanced video + Sixel)
    assert_eq!(
        responses[0].as_slice(),
        b"\x1b[?1;2;4c",
        "first response must be DA1 (submitted first)"
    );
    // DA3 response: DCS ! | 00000000 ST
    assert_eq!(
        responses[1].as_slice(),
        b"\x1bP!|00000000\x1b\\",
        "second response must be DA3 (submitted after DA1)"
    );
}

/// `DecModes::new()` defaults `color_scheme_notifications` (mode 2031) to false.
#[test]
fn dec_modes_new_mode_2031_default_false() {
    use crate::parser::dec_private::DecModes;
    let modes = DecModes::new();
    assert!(
        !modes.color_scheme_notifications,
        "mode 2031 (color scheme notifications) must default to false"
    );
}

// ── OSC 9 / OSC 777 desktop notifications ──────────────────────────────────────

#[test]
fn osc_9_iterm2_form_pushes_notification() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]9;Build finished\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].title, None);
    assert_eq!(core.osc_data.notifications[0].body, "Build finished");
}

#[test]
fn osc_9_conemu_progress_form_is_ignored() {
    // OSC 9 ; 4 ; ... is ConEmu progress, not an iTerm2 notification.
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]9;4;1;50\x07");
    assert!(core.osc_data.notifications.is_empty());
}

#[test]
fn osc_9_empty_body_is_ignored() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]9;\x07");
    assert!(core.osc_data.notifications.is_empty());
}

#[test]
fn osc_777_notify_pushes_title_and_body() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]777;notify;CI;passed\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].title.as_deref(), Some("CI"));
    assert_eq!(core.osc_data.notifications[0].body, "passed");
}

#[test]
fn osc_777_empty_title_becomes_none() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]777;notify;;body only\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].title, None);
    assert_eq!(core.osc_data.notifications[0].body, "body only");
}

#[test]
fn osc_777_non_notify_subcommand_is_ignored() {
    let mut core = TerminalCore::new(24, 80);
    core.advance(b"\x1b]777;other;x;y\x07");
    assert!(core.osc_data.notifications.is_empty());
}
