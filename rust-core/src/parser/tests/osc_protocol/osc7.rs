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

test_osc_7_hostname!(
    osc7_dotted_dns_host_preserved,
    b"file://build01.example.com/home/user",
    cwd "/home/user",
    host Some("build01.example.com")
);

test_osc_7_hostname!(
    osc7_uppercase_localhost_yields_none_host,
    b"file://LOCALHOST/home/user",
    cwd "/home/user",
    host None
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

// ── OSC 99 action round-trip (a=report / i=<id>) ────────────────────────────────

/// INTENT: `a=report` sets the notification's report flag and `i=<id>` is parsed
/// and surfaced on the finalized notification.
#[test]
fn osc_99_a_report_sets_report_flag_and_id() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;i=abc:a=report;Click me\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    let n = &core.osc_data.notifications[0];
    assert_eq!(n.body, "Click me");
    assert!(n.report, "a=report must set the report flag");
    assert_eq!(n.id.as_deref(), Some("abc"));
}

/// INTENT: a notification without `a=report` has report=false (and a no-id
/// notification has id=None).
#[test]
fn osc_99_without_report_has_report_false_and_no_id() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;;plain\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    let n = &core.osc_data.notifications[0];
    assert!(!n.report, "no a=report must leave report=false");
    assert_eq!(n.id, None, "no i= must leave id=None");
}

/// INTENT: `a=focus,report` enables report (comma-separated list); a leading `-`
/// on `report` (`a=-report`) removes it.
#[test]
fn osc_99_a_actions_list_and_removal() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;i=1:a=focus,report;x\x07");
    assert!(core.osc_data.notifications[0].report);

    let mut core = make_core!();
    core.advance(b"\x1b]99;i=2:a=-report;y\x07");
    assert!(!core.osc_data.notifications[0].report);
}

/// INTENT: a `report` flag set on any chunk (even a non-final one) carries
/// through to the finalized notification.
#[test]
fn osc_99_report_flag_persists_across_chunks() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;i=9:d=0:a=report:p=title;T\x07");
    core.advance(b"\x1b]99;i=9:d=1:p=body;B\x07");
    assert_eq!(core.osc_data.notifications.len(), 1);
    assert!(core.osc_data.notifications[0].report);
    assert_eq!(core.osc_data.notifications[0].id.as_deref(), Some("9"));
}

/// INTENT: the response API pushes the exact `OSC 99 ; i=<id> ; <button> ST`
/// bytes (BEL-terminated) onto pending responses for a button click.
#[test]
fn osc_99_response_button_pushes_exact_bytes() {
    let mut core = make_core!();
    core.push_notification_action_response("abc", Some(2), false);
    assert_eq!(core.pending_responses().len(), 1);
    assert_eq!(core.pending_responses()[0], b"\x1b]99;i=abc;2\x07");
}

/// INTENT: plain activation (no button) pushes `OSC 99 ; i=<id> ; ST` with an
/// empty button field.
#[test]
fn osc_99_response_activation_pushes_empty_button() {
    let mut core = make_core!();
    core.push_notification_action_response("xy", None, false);
    assert_eq!(core.pending_responses()[0], b"\x1b]99;i=xy;\x07");
}

/// INTENT: a close report (`c=1` workflow) pushes the `p=close` variant
/// `OSC 99 ; i=<id> : p=close ; ST`.
#[test]
fn osc_99_response_close_pushes_p_close_variant() {
    let mut core = make_core!();
    core.push_notification_action_response("z", None, true);
    assert_eq!(core.pending_responses()[0], b"\x1b]99;i=z:p=close;\x07");
}

/// INTENT (edge): an empty id still produces well-formed framing `i=;` — the
/// app gets back an empty-id response rather than a malformed sequence.
#[test]
fn osc_99_response_empty_id_is_well_formed() {
    let mut core = make_core!();
    core.push_notification_action_response("", None, false);
    assert_eq!(core.pending_responses()[0], b"\x1b]99;i=;\x07");
}

/// INTENT (edge): a button click on a close report combines both — `i=<id>:p=
/// close` metadata AND the button number in the payload field.
#[test]
fn osc_99_response_close_with_button_combines_both() {
    let mut core = make_core!();
    core.push_notification_action_response("q", Some(5), true);
    assert_eq!(core.pending_responses()[0], b"\x1b]99;i=q:p=close;5\x07");
}

/// INTENT (injection-safety doc): an id can only ever be a single colon-free,
/// semicolon-free field because the OSC framing strips `;` and the metadata
/// split strips `:`. We still confirm a benign id with safe punctuation
/// round-trips verbatim, documenting that no escaping is performed (none is
/// needed for parser-sourced ids).
#[test]
fn osc_99_response_id_with_safe_punctuation_round_trips() {
    let mut core = make_core!();
    core.push_notification_action_response("app-42_id.x", None, false);
    assert_eq!(core.pending_responses()[0], b"\x1b]99;i=app-42_id.x;\x07");
}

/// INTENT (end-to-end): an OSC 99 with `i=ID:a=report` is parsed, the report
/// flag is surfaced, and the host can then enqueue the matching action response
/// — confirming the full report round-trip wiring.
#[test]
fn osc_99_report_then_action_response_round_trip() {
    let mut core = make_core!();
    core.advance(b"\x1b]99;i=ID7:a=report;notif\x07");
    let n = &core.osc_data.notifications[0];
    assert!(n.report);
    assert_eq!(n.id.as_deref(), Some("ID7"));
    // Host acts on it (button 1).
    core.push_notification_action_response("ID7", Some(1), false);
    assert_eq!(core.pending_responses()[0], b"\x1b]99;i=ID7;1\x07");
}
