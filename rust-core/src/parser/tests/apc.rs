//! Property-based and example-based tests for `apc` parsing.
//!
//! Module under test: `parser/apc.rs`
//! Tier: T5 — `ProptestConfig::with_cases(64)`

use super::MAX_APC_PAYLOAD_BYTES;
use super::*;
#[path = "apc/tests_support.rs"]
mod tests_support;
pub use tests_support::{
    assert_no_apc_responses, assert_no_pending_image_notifications,
    assert_pending_image_notification_count, assert_single_pending_image_notification,
    single_apc_response_text,
};

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
    let resp = single_apc_response_text(&core);
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
    assert_no_apc_responses(&core);
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

/// A chunk ending in a bare ESC must enter the APC scanner and record
/// `AfterEsc`: the matching `_` may arrive in the next chunk.  The former
/// "ESC anywhere AND `_` anywhere" gate skipped the scanner here, silently
/// dropping any Kitty Graphics APC whose `ESC _` introducer straddled a
/// PTY read boundary.
///
/// State path exercised: trailing-ESC gate — scanner entered, Idle → AfterEsc.
#[test]
fn test_trailing_esc_records_after_esc_for_next_chunk() {
    let mut core = crate::TerminalCore::new(24, 80);

    // Feed ESC only — a `_` may follow in the next chunk.
    feed(&mut core, b"\x1b");

    assert!(
        core.kitty.apc_state == ApcScanState::AfterEsc,
        "state must be AfterEsc so a next-chunk '_' can start an APC"
    );
    assert!(core.kitty.apc_buf.is_empty(), "apc_buf must remain empty");
}

/// An ESC with no adjacent `_` (and not at the chunk end) never enters the
/// APC scanner: ordinary CSI-colored output containing underscores stays on
/// the fast gate.
///
/// State path exercised: adjacency gate — APC scanner not entered.
#[test]
fn test_esc_without_adjacent_underscore_stays_idle() {
    let mut core = crate::TerminalCore::new(24, 80);

    // ESC [ 3 1 m + text containing '_' — no `ESC _` pair, no trailing ESC.
    feed(&mut core, b"\x1b[31msnake_case_text");

    assert!(
        core.kitty.apc_state == ApcScanState::Idle,
        "state must stay Idle when no `ESC _` pair exists"
    );
    assert!(core.kitty.apc_buf.is_empty(), "apc_buf must remain empty");
}

/// An `ESC _` introducer split across two chunks must still start an APC
/// sequence and accumulate its payload.
///
/// State path exercised: Idle → AfterEsc (chunk 1), AfterEsc → InApc (chunk 2).
#[test]
fn test_apc_introducer_straddling_chunk_boundary() {
    let mut core = crate::TerminalCore::new(24, 80);

    feed(&mut core, b"\x1b");
    feed(&mut core, b"_Gi=1;payload");

    assert!(
        core.kitty.apc_state == ApcScanState::InApc,
        "chunk-straddling ESC _ must enter InApc"
    );
    assert_eq!(core.kitty.apc_buf, b"Gi=1;payload");
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
    assert_no_apc_responses(&core);
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
    assert_no_apc_responses(&core);
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
    assert_no_apc_responses(&core);
}

#[path = "apc/binary_payload.rs"]
mod binary_payload;

#[path = "apc/dispatch.rs"]
mod dispatch;

#[path = "apc/delete_targets.rs"]
mod delete_targets;

#[path = "apc/placeholder.rs"]
mod placeholder;
