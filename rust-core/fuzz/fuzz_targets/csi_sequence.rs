#![no_main]
use kuro_core::TerminalCore;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if data.is_empty() {
        return;
    }
    let mut term = TerminalCore::new(24, 80);
    // Build CSI sequence: ESC [ <data[0..n-1]> <data[n-1] as final byte>
    let params = &data[..data.len().saturating_sub(1)];
    let final_byte = data[data.len() - 1];

    let mut seq = Vec::with_capacity(data.len() + 2);
    seq.extend_from_slice(b"\x1b[");
    seq.extend_from_slice(params);
    seq.push(final_byte);
    term.advance(&seq);
    // Must not panic
});
