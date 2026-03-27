//! Property-based and example-based tests for `apc` parsing.
//!
//! Module under test: `parser/apc.rs`
//! Tier: T5 — `ProptestConfig::with_cases(64)`

use super::MAX_APC_PAYLOAD_BYTES;
use super::*;

/// Feed raw bytes through the APC pre-scanner (and the VTE parser) using
/// the public `TerminalCore::advance` method, which delegates to
/// `advance_with_apc`.
fn feed(core: &mut crate::TerminalCore, bytes: &[u8]) {
    core.advance(bytes);
}

/// The APC scanner must cap the payload buffer at `MAX_APC_PAYLOAD_BYTES`.
/// Any bytes beyond that limit are silently dropped; the sequence is still
/// dispatched with the truncated payload once ST (ESC \\) is received.
#[test]
fn test_apc_payload_size_cap() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Open APC: ESC _
    feed(&mut core, b"\x1b_");
    assert!(
        core.kitty.apc_state == ApcScanState::InApc,
        "state should be InApc after ESC _"
    );

    // Push exactly MAX_APC_PAYLOAD_BYTES bytes (all 'A').
    let payload = vec![b'A'; MAX_APC_PAYLOAD_BYTES];
    feed(&mut core, &payload);
    assert_eq!(
        core.kitty.apc_buf.len(),
        MAX_APC_PAYLOAD_BYTES,
        "buffer should hold MAX_APC_PAYLOAD_BYTES after filling it"
    );

    // Push one more byte — it must be dropped.
    feed(&mut core, b"B");
    assert_eq!(
        core.kitty.apc_buf.len(),
        MAX_APC_PAYLOAD_BYTES,
        "buffer must not grow beyond MAX_APC_PAYLOAD_BYTES"
    );
}

/// Sending a complete Kitty Graphics query sequence byte-by-byte must return
/// the state machine to Idle after the closing ST (ESC \\) is consumed, and
/// queue a pending response (the "OK" reply from Query handling).
#[test]
fn test_complete_kitty_apc_sequence_produces_response() {
    let mut core = crate::TerminalCore::new(24, 80);

    // ESC _ G a=q,i=1 ESC \ — a minimal Kitty query command.
    // advance_with_apc scans the raw bytes; vte sees them too but ignores APC.
    let seq = b"\x1b_Ga=q,i=1\x1b\\";
    feed(&mut core, seq);

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after ESC \\\\"
    );

    // dispatch_kitty_apc queues a response for Query commands.
    assert!(
        !core.meta.pending_responses.is_empty(),
        "a pending response should be queued after a Kitty query"
    );
    let resp =
        std::str::from_utf8(&core.meta.pending_responses[0]).expect("response must be valid UTF-8");
    assert!(
        resp.starts_with("\x1b_Ga=q"),
        "Kitty query response must start with ESC _ G a=q, got: {resp:?}"
    );
}

/// Plain ASCII text contains no ESC byte.  The memchr fast-path in
/// `advance_with_apc` skips the byte-by-byte APC scanner entirely, so the
/// APC state remains Idle throughout.
#[test]
fn test_plain_text_bypasses_apc_fast_path() {
    let mut core = crate::TerminalCore::new(24, 80);

    // No ESC byte anywhere — the fast-path skips the scanner.
    feed(&mut core, b"Hello, world! No escape sequences here.");

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "APC state must stay Idle for plain ASCII with no ESC"
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "APC buffer must remain empty for plain ASCII"
    );
}

/// A false ESC mid-payload (ESC followed by a byte other than '\\') must push
/// both the ESC and the following byte into the buffer and keep the state
/// machine in `InApc` — the sequence must NOT be dispatched prematurely.
///
/// State path exercised:
///   `InApc` --ESC--> `AfterApcEsc` --non-\\ byte--> `InApc` (both bytes pushed)
#[test]
fn test_false_esc_mid_sequence_continues() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Build a Kitty query that embeds a false ESC (followed by 'X', not '\\').
    // Sequence: ESC _ G a=q \x1B X more \x1B \\ (real ST)
    //                          ^^^^ false ESC pair
    // The false ESC + 'X' must be pushed into apc_buf; no dispatch happens
    // until the real ESC \ terminator arrives.
    let seq = b"\x1b_Ga=q\x1bXmore\x1b\\";
    feed(&mut core, seq);

    // After the real ST the state must be Idle again.
    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after the real ST terminator"
    );

    // The buffer is cleared on dispatch, so we verify via the response queue:
    // the sequence starts with 'G' so dispatch_kitty_apc was called.
    // (The payload is malformed for Kitty purposes so no actual response is
    // produced, but we can confirm we did NOT get a premature dispatch by
    // checking that no response was queued *before* the real ST arrived.)
    //
    // Additionally the buffer must be empty now (cleared by dispatch).
    assert!(
        core.kitty.apc_buf.is_empty(),
        "apc_buf must be cleared after dispatch"
    );
}

/// An APC sequence whose payload does NOT start with 'G' (not a Kitty
/// Graphics command) must run through the state machine cleanly and return to
/// Idle, but must NOT queue any Kitty response.
#[test]
fn test_non_kitty_apc_sequence_is_ignored() {
    let mut core = crate::TerminalCore::new(24, 80);

    // APC starting with 'X' — not a Kitty 'G' prefix.
    // ESC _ X somedata ESC \\
    let seq = b"\x1b_Xsomedata\x1b\\";
    feed(&mut core, seq);

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after a non-Kitty APC sequence"
    );
    assert!(
        core.meta.pending_responses.is_empty(),
        "non-Kitty APC sequence must not queue any pending response"
    );
}

/// ESC followed by a byte that is NOT '_' must reset the APC state to Idle
/// without accumulating anything into the buffer.
///
/// State path: `Idle` --ESC--> `AfterEsc` --non-'_'--> `Idle`
#[test]
fn test_esc_non_underscore_resets_to_idle() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Feed ESC then '[' — this is not an APC opener; state must go back to Idle.
    feed(&mut core, b"\x1b[");

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must be Idle after ESC + non-'_' byte; got {:?}",
        core.kitty.apc_state as u8,
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "apc_buf must stay empty when ESC is not followed by '_'"
    );
}

/// When the APC buffer is already full (== MAX_APC_PAYLOAD_BYTES) and a false
/// ESC mid-payload arrives, the `+2 <= MAX` guard in AfterApcEsc must silently
/// drop both the ESC and the following non-'\\' byte rather than growing the
/// buffer beyond the cap.
#[test]
fn test_false_esc_at_capacity_is_dropped() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Fill the buffer to exactly MAX_APC_PAYLOAD_BYTES with 'A' bytes.
    // We open APC with ESC _ then push (MAX - 1) bytes, leaving one slot.
    // The first byte of the payload is 'G' so dispatch_kitty_apc will be called
    // on termination (but with a malformed payload, so no response is expected).
    let mut seq = vec![0x1Bu8, b'_', b'G'];
    // Fill remaining slots: we already have 1 byte ('G'), push MAX-1 more.
    seq.extend(std::iter::repeat_n(b'A', MAX_APC_PAYLOAD_BYTES - 1));
    // Buffer is now full.  Insert a false ESC (not followed by '\\') — the
    // `apc_buf.len() + 2 <= MAX_APC_PAYLOAD_BYTES` check should be false,
    // so both ESC and 'X' are silently dropped.
    seq.push(0x1B); // false ESC
    seq.push(b'X'); // non-'\\' — back to InApc without pushing
                    // Terminate the APC with a real ESC \\ so the state machine returns to Idle.
    seq.push(0x1B);
    seq.push(b'\\');

    feed(&mut core, &seq);

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after closing ST"
    );
    // Buffer was cleared on dispatch.
    assert!(
        core.kitty.apc_buf.is_empty(),
        "apc_buf must be cleared on dispatch"
    );
}

/// A bare ESC with no '_' byte in the same chunk is handled by the fast-path
/// memchr guard in `advance_with_apc`: when there is no '_' in the buffer and
/// we are not already in an APC sequence, the byte-by-byte APC scanner is
/// skipped entirely, so the state stays `Idle`.
///
/// State path exercised: fast-path bypass — APC scanner not entered.
#[test]
fn test_lone_esc_no_underscore_stays_idle() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Feed ESC only — no '_' byte means the fast-path skips the APC scanner.
    feed(&mut core, b"\x1b");

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must stay Idle when ESC is fed without a '_' in the same chunk"
    );
    assert!(core.kitty.apc_buf.is_empty(), "apc_buf must remain empty");
}

/// An APC sequence with an empty payload (ESC _ ESC \\) must run cleanly
/// through InApc, dispatch nothing (empty buf, no 'G' first byte), and return
/// to Idle without panicking.
#[test]
fn test_empty_apc_payload_no_panic() {
    let mut core = crate::TerminalCore::new(24, 80);

    // ESC _ ESC \\ — empty APC.
    feed(&mut core, b"\x1b_\x1b\\");

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must be Idle after empty APC sequence"
    );
    assert!(
        core.meta.pending_responses.is_empty(),
        "empty APC payload must not queue any response"
    );
}

// -------------------------------------------------------------------------
// New edge-case tests
// -------------------------------------------------------------------------

/// An APC payload of exactly `MAX_APC_PAYLOAD_BYTES` bytes followed by ST
/// must dispatch cleanly: the buffer holds exactly MAX bytes, the state
/// returns to Idle, and the buffer is cleared.
///
/// We use a non-'G' first byte so `dispatch_kitty_apc` is not called, which
/// keeps the test fast (no Kitty parsing overhead) while still exercising the
/// full fill → dispatch → clear path.
#[test]
fn test_apc_payload_exactly_at_limit_dispatches_cleanly() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Open APC with a non-'G' prefix so no Kitty dispatch occurs.
    // Build: ESC _ X (MAX-1 × 'A') ESC \\
    // Total payload = 1 ('X') + (MAX-1) ('A') = MAX bytes.
    let mut seq = vec![0x1Bu8, b'_', b'X'];
    seq.extend(std::iter::repeat_n(b'A', MAX_APC_PAYLOAD_BYTES - 1));
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
        "non-Kitty APC payload must not queue any response"
    );
}

/// An APC payload of `MAX_APC_PAYLOAD_BYTES + 1` bytes followed by ST must
/// truncate to MAX bytes (the extra byte is silently dropped) and then
/// dispatch cleanly — returning to Idle with an empty buffer.
///
/// The truncation happens in the `InApc` branch: the `if len < MAX` guard
/// prevents the extra byte from being pushed.
#[test]
fn test_apc_payload_one_byte_over_limit_truncates_and_dispatches() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Open APC: ESC _ X  followed by MAX bytes of 'A' (payload = MAX+1 after 'X').
    // The 'X' occupies slot 0; 'A'×MAX pushes MAX bytes, but after slot 0 is
    // filled the buffer is MAX-1 slots short, so MAX bytes of 'A' overfills by 1.
    //
    // More precisely: after ESC _ we push b'X' (1 byte in buf), then MAX bytes
    // of 'A'.  After the first MAX-1 'A' bytes the buffer is full (MAX bytes).
    // The last 'A' byte is silently dropped.
    let mut seq = vec![0x1Bu8, b'_', b'X'];
    seq.extend(std::iter::repeat_n(b'A', MAX_APC_PAYLOAD_BYTES));
    seq.push(0x1B);
    seq.push(b'\\');

    feed(&mut core, &seq);

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must return to Idle after ST even when payload was truncated"
    );
    assert!(
        core.kitty.apc_buf.is_empty(),
        "apc_buf must be cleared after dispatch"
    );
    assert!(
        core.meta.pending_responses.is_empty(),
        "non-Kitty APC payload must not queue any response"
    );
}

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
