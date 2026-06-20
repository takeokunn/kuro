// ── handle_osc_7 hostname preservation ───────────────────────────────────────

test_osc_7_hostname!(
    osc7_localhost_yields_none_host,
    b"file://localhost/home/user",
    cwd "/home/user",
    host None
);

test_osc_7_hostname!(
    osc7_empty_host_yields_none,
    b"file:///tmp",
    cwd "/tmp",
    host None
);

test_osc_7_hostname!(
    osc7_remote_host_preserved,
    b"file://myhost/home/user",
    cwd "/home/user",
    host Some("myhost")
);

test_osc_7_hostname_reset!(
    osc7_host_cleared_on_localhost,
    first b"file://remotehost/srv",
    second b"file://localhost/home",
    cwd "/home"
);

// ── DA3 ordering / Mode 2031 default state (FR-115 / FR-117) ─────────────────

/// DA3 (`CSI = c`) issued after DA1 (`CSI c`) queues responses in submission
/// order — DA1 response first, DA3 response second.
#[test]
fn da1_then_da3_responses_in_submission_order() {
    let mut core = make_core!();
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
    let mut core = make_core!();
    core.advance(b"\x1b]9;Build finished\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].title, None);
    assert_eq!(core.osc_data.notifications[0].body, "Build finished");
}

#[test]
fn osc_9_conemu_progress_form_is_ignored() {
    // OSC 9 ; 4 ; ... is ConEmu progress, not an iTerm2 notification.
    let mut core = make_core!();
    core.advance(b"\x1b]9;4;1;50\x07");
    assert!(core.osc_data.notifications.is_empty());
}

#[test]
fn osc_9_empty_body_is_ignored() {
    let mut core = make_core!();
    core.advance(b"\x1b]9;\x07");
    assert!(core.osc_data.notifications.is_empty());
}

#[test]
fn osc_777_notify_pushes_title_and_body() {
    let mut core = make_core!();
    core.advance(b"\x1b]777;notify;CI;passed\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].title.as_deref(), Some("CI"));
    assert_eq!(core.osc_data.notifications[0].body, "passed");
}

#[test]
fn osc_777_empty_title_becomes_none() {
    let mut core = make_core!();
    core.advance(b"\x1b]777;notify;;body only\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].title, None);
    assert_eq!(core.osc_data.notifications[0].body, "body only");
}

#[test]
fn osc_777_non_notify_subcommand_is_ignored() {
    let mut core = make_core!();
    core.advance(b"\x1b]777;other;x;y\x07");
    assert!(core.osc_data.notifications.is_empty());
}
