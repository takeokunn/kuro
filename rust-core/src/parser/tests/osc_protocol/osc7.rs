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

// ── OSC 99 Kitty desktop notifications ──────────────────────────────────────────

/// INTENT: the minimal Kitty form `OSC 99 ; ; <text>` (empty metadata) yields a
/// single notification with body = the text and no title.
#[test]
fn osc_99_minimal_form_sets_body_no_title() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;;Hello world\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].title, None);
    assert_eq!(core.osc_data.notifications[0].body, "Hello world");
}

/// INTENT: `e=1` marks the payload as base64; it must be decoded to UTF-8 text
/// before being stored as the body.
#[test]
fn osc_99_base64_body_is_decoded() {
    let mut core = make_core!();
    // base64("Hi there") = "SGkgdGhlcmU="
    core.advance(b"\x1b]99;e=1;SGkgdGhlcmU=\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].title, None);
    assert_eq!(core.osc_data.notifications[0].body, "Hi there");
}

/// INTENT: `p=title` routes the payload into the title field rather than the body.
#[test]
fn osc_99_p_title_sets_title() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;p=title;My Title\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(
        core.osc_data.notifications[0].title.as_deref(),
        Some("My Title")
    );
    assert_eq!(core.osc_data.notifications[0].body, "");
}

/// INTENT: chunks with the same `i=<id>` and `d=0` accumulate; the notification
/// is only pushed when the final `d=1` chunk arrives, combining title + body.
#[test]
fn osc_99_chunked_title_then_body_finalizes_on_done() {
    let mut core = make_core!();
    // First chunk: title, more to follow (d=0).
    core.advance(b"\x1b]99;i=42:d=0:p=title;Greetings\x07");
    assert!(
        core.osc_data.notifications.is_empty(),
        "d=0 chunk must not finalize yet"
    );
    // Final chunk: body, done (d=1).
    core.advance(b"\x1b]99;i=42:d=1:p=body;the body text\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(
        core.osc_data.notifications[0].title.as_deref(),
        Some("Greetings")
    );
    assert_eq!(core.osc_data.notifications[0].body, "the body text");
}

/// INTENT: two `d=0` body chunks with the same id accumulate their payloads in
/// order; the joined text is pushed on `d=1`.
#[test]
fn osc_99_body_chunks_accumulate_in_order() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;i=7:d=0:p=body;Hello \x07");
    core.advance(b"\x1b]99;i=7:d=1:p=body;World\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].body, "Hello World");
}

/// INTENT: malformed metadata pairs (no `=`, unknown keys) are ignored gracefully
/// and the payload still produces a body notification.
#[test]
fn osc_99_malformed_metadata_ignored_gracefully() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;garbage:nokey:zz=1;still works\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].title, None);
    assert_eq!(core.osc_data.notifications[0].body, "still works");
}

/// INTENT: invalid base64 under `e=1` is rejected without panicking and produces
/// no notification.
#[test]
fn osc_99_invalid_base64_is_ignored() {
    let mut core = make_core!();
    // "!!!" is not valid base64 (length not multiple of 4 / invalid chars).
    core.advance(b"\x1b]99;e=1;!!!\x07");
    assert!(core.osc_data.notifications.is_empty());
}

/// INTENT: a single-shot sequence with no `i=` finalizes immediately even though
/// `d=0` is present, because chunking requires an id to group on.
#[test]
fn osc_99_no_id_finalizes_immediately_despite_d0() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;d=0;flush me\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].body, "flush me");
}

/// INTENT: a payload containing semicolons (which the VTE parser splits into
/// separate params) is rejoined so the body preserves the embedded `;`.
#[test]
fn osc_99_payload_with_semicolons_is_rejoined() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;;a;b;c\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert_eq!(core.osc_data.notifications[0].body, "a;b;c");
}
