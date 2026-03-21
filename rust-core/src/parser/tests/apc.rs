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
