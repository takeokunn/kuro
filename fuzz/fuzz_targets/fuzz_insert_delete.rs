#![no_main]
use libfuzzer_sys::fuzz_target;
use kuro_core::TerminalCore;

fuzz_target!(|data: &[u8]| {
    let mut term = TerminalCore::new(24, 80);
    // First print some content including wide chars
    term.advance("日本語テスト".as_bytes());
    // Then apply insert/delete operations with fuzz data as parameter
    // ICH (insert char): ESC [ N @
    // DCH (delete char): ESC [ N P
    // IL (insert line): ESC [ N L
    // DL (delete line): ESC [ N M
    let mut seq = Vec::with_capacity(data.len() + 3);
    seq.extend_from_slice(b"\x1b[");
    seq.extend_from_slice(data);
    seq.push(b'P'); // DCH: delete character
    term.advance(&seq);
    // Must not panic
});
