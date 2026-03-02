#![no_main]
use libfuzzer_sys::fuzz_target;
use kuro_core::TerminalCore;

fuzz_target!(|data: &[u8]| {
    let mut term = TerminalCore::new(24, 80);
    term.advance(data);
});
