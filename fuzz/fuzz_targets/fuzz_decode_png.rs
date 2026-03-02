#![no_main]
use libfuzzer_sys::fuzz_target;
use kuro_core::TerminalCore;
use base64::Engine as _;

fuzz_target!(|data: &[u8]| {
    // Exercise PNG decode path by sending a Kitty image sequence with PNG format
    // Kitty protocol: ESC _ G a=T,f=100,m=0;<base64 data> ESC backslash
    let b64 = base64::engine::general_purpose::STANDARD.encode(data);
    let kitty_seq = format!("\x1b_Ga=T,f=100,m=0;{}\x1b\\", b64);
    let mut term = TerminalCore::new(24, 80);
    term.advance(kitty_seq.as_bytes());
});
