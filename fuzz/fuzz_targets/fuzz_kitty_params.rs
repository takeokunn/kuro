#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let _ = kuro_core::parser::kitty::KittyParams::parse(data);
});
