#![no_main]
use libfuzzer_sys::fuzz_target;
use kuro_core::TerminalCore;

fuzz_target!(|data: &[u8]| {
    // Exercise APC payload processing through advance()
    // Wrap data in APC framing: ESC _ <data> ESC backslash
    let mut payload = Vec::with_capacity(data.len() + 4);
    payload.extend_from_slice(b"\x1b_");  // ESC _  (APC start)
    payload.extend_from_slice(data);
    payload.extend_from_slice(b"\x1b\\"); // ESC \  (ST terminator)
    let mut term = TerminalCore::new(24, 80);
    term.advance(&payload);
});
