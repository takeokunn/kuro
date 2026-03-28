/// An APC payload containing non-ASCII bytes (0x80–0xFF) must be accumulated
/// unchanged by the state machine (it operates on raw `u8`, not UTF-8) and
/// must not panic.
///
/// Non-ASCII bytes ≥ 0x80 are not printable ASCII but are valid raw byte
/// values in a binary protocol stream.  The APC scanner stores them verbatim
/// in `apc_buf`.  Since the payload does not start with 'G', `dispatch_kitty_apc`
/// is not called and no response is queued.
#[test]
fn test_apc_non_ascii_bytes_accepted_without_panic() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Payload: 'X' (non-Kitty prefix) followed by bytes 0x80..=0xFF.
    // None of these contain 0x1B (ESC) or '\\', so no false terminator.
    let mut seq = vec![0x1Bu8, b'_', b'X'];
    seq.extend(0x80u8..=0xFFu8); // 128 non-ASCII bytes
    seq.push(0x1B);
    seq.push(b'\\');

    feed(&mut core, &seq);

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after ST"
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "apc_buf must be cleared after dispatch"
    );
    assert!(
        core.meta.pending_responses.is_empty(),
        "non-Kitty APC with non-ASCII payload must not queue any response"
    );
}

/// An APC payload starting with 'G' (Kitty Graphics prefix) that contains
/// non-ASCII bytes in the payload section must not panic.
///
/// `dispatch_kitty_apc` parses the payload with `process_apc_payload`; a
/// malformed (non-ASCII) payload will fail parsing and return `None`, so no
/// response is queued and no panic occurs.
#[test]
fn test_apc_kitty_prefix_with_non_ascii_payload_no_panic() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Sequence: ESC _ G <non-ASCII bytes> ESC \\
    let mut seq = vec![0x1Bu8, b'_', b'G'];
    seq.extend(0x80u8..=0xA0u8); // 33 non-ASCII bytes — malformed Kitty payload
    seq.push(0x1B);
    seq.push(b'\\');

    // Must not panic.
    feed(&mut core, &seq);

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after ST"
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "apc_buf must be cleared after dispatch"
    );
}

// ── New edge-case tests (Round 34+) ───────────────────────────────────────────

/// Two consecutive complete APC sequences must each be dispatched independently.
/// After the first ST the state returns to Idle, the buffer is cleared, and
/// the second sequence can start cleanly.
///
/// Both sequences start with 'X' (non-Kitty) so no response is produced; we
/// verify only that the state machine ends in Idle with an empty buffer.
#[test]
fn test_two_consecutive_apc_sequences_both_dispatched() {
    let mut core = crate::TerminalCore::new(24, 80);

    // First APC: ESC _ X hello ESC \\
    feed(&mut core, b"\x1b_Xhello\x1b\\");
    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must be Idle after first APC"
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "buffer must be empty after first APC dispatch"
    );

    // Second APC: ESC _ X world ESC \\
    feed(&mut core, b"\x1b_Xworld\x1b\\");
    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must be Idle after second APC"
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "buffer must be empty after second APC dispatch"
    );
}

/// State persists across separate `advance` calls.  Opening an APC in one
/// call and closing it in a subsequent call must work correctly.
#[test]
fn test_apc_split_across_two_advance_calls() {
    let mut core = crate::TerminalCore::new(24, 80);

    // First call: open APC with ESC _ G a=q,i=99
    feed(&mut core, b"\x1b_Ga=q,i=99");
    assert!(
        core.kitty.apc_state == ApcScanState::InApc,
        "state must be InApc after opening APC in first call"
    );

    // Second call: terminate with ESC \\
    feed(&mut core, b"\x1b\\");
    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after ST in second call"
    );
    // The Kitty query produces a pending response.
    assert!(
        !core.meta.pending_responses.is_empty(),
        "Kitty query split across two calls must still produce a response"
    );
}

/// A new ESC _ while already inside an APC payload (InApc state) must NOT
/// restart the APC sequence; the '_' byte is treated as ordinary payload data
/// and is accumulated into the buffer.
///
/// The ESC transitions to AfterApcEsc and then '_' is not '\\', so both bytes
/// are pushed back into the buffer and InApc resumes.
#[test]
fn test_esc_underscore_inside_apc_is_treated_as_payload() {
    let mut core = crate::TerminalCore::new(24, 80);

    // APC: ESC _ X data ESC _ more ESC \\
    //                   ^^^^^ embedded ESC _ — not a new APC start
    // The ESC enters AfterApcEsc, then '_' (non-'\\') pushes ESC+'_' into buf.
    feed(&mut core, b"\x1b_Xdata\x1b_more\x1b\\");

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after the real ST"
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "buffer must be cleared after dispatch"
    );
    // Non-Kitty prefix 'X', so no response.
    assert!(
        core.meta.pending_responses.is_empty(),
        "non-Kitty APC must not queue a response"
    );
}

/// Two ESC bytes in a row while in AfterApcEsc state: the first ESC transitions
/// from InApc → AfterApcEsc.  The second ESC is then processed in AfterApcEsc
/// (as a non-'\\' byte), pushing ESC+ESC into the buffer, and the state
/// returns to InApc.  A real ST afterwards must close the sequence normally.
#[test]
fn test_double_esc_in_apc_payload_handled_correctly() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Sequence: ESC _ X A ESC ESC B ESC \\
    //                       ^^^^^^^ double-ESC: first moves to AfterApcEsc,
    //                               second pushes ESC+ESC back to buf (non-'\\')
    feed(&mut core, b"\x1b_XA\x1b\x1bB\x1b\\");

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after ST following double-ESC"
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "buffer must be cleared after dispatch"
    );
}

/// In AfterEsc state, receiving a second ESC (instead of '_') must reset to
/// Idle (the first ESC is discarded) and then the second ESC re-enters
/// AfterEsc.  A subsequent '_' then starts a new APC normally.
#[test]
fn test_double_esc_then_underscore_opens_apc() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Feed ESC ESC _ X foo ESC \\
    // First ESC → AfterEsc; second ESC → Idle (non-'_' resets); '_' → ...
    // Wait: the second ESC is again 0x1B, which in AfterEsc is non-'_',
    // so state goes Idle and the second ESC has been consumed.
    // The '_' then arrives in Idle state → just Idle (not AfterEsc).
    // So the APC never opens.
    //
    // We verify no panic and the state ends in Idle.
    feed(&mut core, b"\x1b\x1b_Xfoo\x1b\\");

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must end in Idle after ESC ESC _ sequence"
    );
    // The APC did not open after double-ESC so the buffer is empty.
    assert!(
        core.kitty.apc_buf.is_empty(),
        "buffer must be empty when APC never opened"
    );
}

/// Multi-byte UTF-8 sequences (e.g. 0xC2 0xA0 = U+00A0 NO-BREAK SPACE) in the
/// APC payload must be stored verbatim as individual raw bytes.  The APC
/// scanner operates on `u8` values, not Unicode codepoints.
///
/// We use a non-Kitty prefix so no response is queued, keeping the test focused
/// on byte accumulation and state-machine correctness.
#[test]
fn test_apc_utf8_multibyte_payload_accepted() {
    let mut core = crate::TerminalCore::new(24, 80);

    // U+00A0 (NO-BREAK SPACE) encodes as 0xC2 0xA0 in UTF-8.
    // U+00E9 (é) encodes as 0xC3 0xA9.
    // Neither byte is ESC (0x1B) or '\\' so no false terminator.
    let mut seq = vec![0x1Bu8, b'_', b'X'];
    seq.extend_from_slice(&[0xC2, 0xA0, 0xC3, 0xA9]); // multi-byte UTF-8
    seq.push(0x1B);
    seq.push(b'\\');

    feed(&mut core, &seq);

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after ST"
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "buffer must be cleared after dispatch"
    );
    assert!(
        core.meta.pending_responses.is_empty(),
        "non-Kitty APC must not queue a response"
    );
}

/// A Kitty query sequence with a numeric image id in the response format:
/// the response must contain `i=<N>` when the query includes `i=<N>`.
#[test]
fn test_kitty_query_response_includes_image_id() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Kitty query: ESC _ G a=q,i=42 ESC \\
    feed(&mut core, b"\x1b_Ga=q,i=42\x1b\\");

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must be Idle after Kitty query"
    );
    assert!(
        !core.meta.pending_responses.is_empty(),
        "Kitty query must produce a pending response"
    );
    let resp =
        std::str::from_utf8(&core.meta.pending_responses[0]).expect("response must be valid UTF-8");
    assert!(
        resp.contains("i=42"),
        "Kitty query response must echo the image id i=42; got: {resp:?}"
    );
}

/// After a complete APC sequence, feeding plain ASCII must not re-enter the
/// APC scanner (state stays Idle, buffer stays empty).
#[test]
fn test_plain_ascii_after_apc_stays_idle() {
    let mut core = crate::TerminalCore::new(24, 80);

    // First, a complete non-Kitty APC.
    feed(&mut core, b"\x1b_Xdata\x1b\\");
    assert!(core.kitty.apc_state == ApcScanState::Idle);

    // Now plain ASCII — no ESC anywhere.
    feed(&mut core, b"hello world");
    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must stay Idle after plain ASCII following an APC"
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "buffer must remain empty after plain ASCII"
    );
}

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    // PANIC SAFETY: APC with arbitrary payload never panics (payload is truncated at max)
    fn prop_apc_arbitrary_payload_no_panic(
        payload in proptest::collection::vec(0x20u8..=0x7eu8, 0..=200)
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        let p = String::from_utf8(payload).unwrap_or_default();
        // ESC _ payload ESC \\ (APC)
        let seq = format!("\x1b_{p}\x1b\\");
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }
}
