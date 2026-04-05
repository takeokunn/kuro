#![no_main]
use libfuzzer_sys::fuzz_target;
use kuro_core::TerminalCore;

fuzz_target!(|data: &[u8]| {
    let mut term = TerminalCore::new(24, 80);
    // Build a CSI sequence: ESC [ <data> m
    let mut seq = Vec::with_capacity(data.len() + 3);
    seq.extend_from_slice(b"\x1b[");
    seq.extend_from_slice(data);
    seq.push(b'm');
    term.advance(&seq);
    // Must not panic
});
