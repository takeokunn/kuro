//! VTE parser throughput benchmark (FR-005-01)
//!
//! Measures the time to parse large VTE sequences.
//! Target: >100MB/s throughput.

use criterion::{black_box, criterion_group, criterion_main, Criterion, Throughput};
use kuro_core::TerminalCore;

/// Generate simulated PTY output with various escape sequences
fn generate_vte_output(size_mb: usize) -> Vec<u8> {
    let mut output = Vec::with_capacity(size_mb * 1024 * 1024);

    // Create a mix of:
    // 1. Plain ASCII text (60%)
    // 2. ANSI escape sequences for colors (20%)
    // 3. Cursor movement sequences (10%)
    // 4. Erase sequences (10%)

    let ascii_chunk = b"Hello, World! This is a test of the VTE parser performance. ";
    let color_sequence = b"\x1b[31mRed\x1b[32mGreen\x1b[34mBlue\x1b[0m";
    let cursor_move = b"\x1b[10;20H\x1b[5C\x1b[2D";
    let erase_sequence = b"\x1b[2J\x1b[K";

    while output.len() < size_mb * 1024 * 1024 {
        // Add plain ASCII text
        for _ in 0..10 {
            output.extend_from_slice(ascii_chunk);
        }

        // Add color sequences
        for _ in 0..5 {
            output.extend_from_slice(color_sequence);
        }

        // Add cursor movements
        for _ in 0..3 {
            output.extend_from_slice(cursor_move);
        }

        // Add erase sequences
        for _ in 0..2 {
            output.extend_from_slice(erase_sequence);
        }
    }

    output.truncate(size_mb * 1024 * 1024);
    output
}

/// Generate plain text output (no escape sequences) to test memchr fast path
fn generate_plain_text(size_mb: usize) -> Vec<u8> {
    // Repeat a pattern that fills a line nicely
    let pattern = b"Hello, World! This is plain text for parser benchmarking. ";
    let pattern_len = pattern.len();
    let target_size = size_mb * 1024 * 1024;

    let repeats = target_size / pattern_len + 1;
    let mut output: Vec<u8> = Vec::with_capacity(target_size);
    for _ in 0..repeats {
        output.extend_from_slice(pattern);
    }
    output.truncate(target_size);
    output
}

/// Benchmark VTE parser throughput with different input sizes
fn bench_parser_throughput(c: &mut Criterion) {
    let mut group = c.benchmark_group("parser_throughput");

    // Test with different input sizes: 1MB, 5MB, 10MB
    for size_mb in &[1, 5, 10] {
        let output = generate_vte_output(*size_mb);

        group.throughput(Throughput::Bytes(output.len() as u64));

        group.bench_with_input(format!("{size_mb}MB"), size_mb, |b, &_size_mb| {
            let mut term = TerminalCore::new(24, 80);

            b.iter(|| {
                term.advance(black_box(&output));
            });
        });
    }

    group.finish();
}

/// Benchmark plain text throughput (memchr fast path - no escape sequences)
/// This tests the optimization added in Wave 4 where we skip the APC pre-scanner
/// when no ESC bytes are present in the buffer.
fn bench_plain_text_throughput(c: &mut Criterion) {
    let mut group = c.benchmark_group("plain_text_throughput");

    // Test with different input sizes: 1MB, 5MB, 10MB
    for size_mb in &[1, 5, 10] {
        let output = generate_plain_text(*size_mb);

        group.throughput(Throughput::Bytes(output.len() as u64));

        group.bench_with_input(format!("{size_mb}MB"), size_mb, |b, &_size_mb| {
            let mut term = TerminalCore::new(24, 80);

            b.iter(|| {
                term.advance(black_box(&output));
            });
        });
    }

    group.finish();
}

criterion_group!(
    benches,
    bench_parser_throughput,
    bench_plain_text_throughput
);
criterion_main!(benches);
