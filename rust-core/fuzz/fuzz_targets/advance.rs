#![no_main]
use kuro_core::TerminalCore;
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let mut term = TerminalCore::new(24, 80);
    term.advance(data);
});
