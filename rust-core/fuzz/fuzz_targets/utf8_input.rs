#![no_main]
use kuro_core::TerminalCore;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if data.is_empty() {
        return;
    }
    let mut term = TerminalCore::new(24, 80);
    // Split at midpoint to test partial sequences across calls
    let mid = data.len() / 2;
    term.advance(&data[..mid]);
    term.advance(&data[mid..]);
    // Must not panic
});
