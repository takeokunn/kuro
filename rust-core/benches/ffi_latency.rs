//! FFI call latency benchmark (FR-005-04)
//!
//! Measures the time for FFI function calls.
//! Target: <10μs latency.

use criterion::{black_box, criterion_group, criterion_main, Criterion};
use kuro_core::TerminalCore;

/// Benchmark FFI call latency with varying payloads
fn bench_ffi_latency(c: &mut Criterion) {
    let mut group = c.benchmark_group("ffi_latency");

    // Benchmark cursor position retrieval (common FFI operation)
    group.bench_function("get_cursor", |b| {
        let core = TerminalCore::new(24, 80);

        b.iter(|| {
            black_box((core.cursor_row(), core.cursor_col()));
        });
    });

    // Benchmark resize operation
    group.bench_function("resize", |b| {
        let mut core = TerminalCore::new(24, 80);

        b.iter(|| {
            black_box(core.resize(24, 80));
            black_box(core.resize(50, 200));
            black_box(core.resize(100, 400));
            black_box(core.resize(24, 80)); // Reset
        });
    });

    // Benchmark scrollback access
    group.bench_function("scrollback_line_count", |b| {
        let core = TerminalCore::new(24, 80);

        b.iter(|| {
            black_box(core.scrollback_line_count());
        });
    });

    // Benchmark get_cell
    group.bench_function("get_cell", |b| {
        let mut core = TerminalCore::new(24, 80);

        // Fill screen
        for _row in 0..24 {
            for _col in 0..80 {
                core.advance(&[b'X']);
            }
        }

        b.iter(|| {
            black_box(core.get_cell(12, 40));
        });
    });

    // Benchmark cell update operation
    // NOTE: TerminalCore::new() is moved OUTSIDE b.iter() to measure only
    // the advance() calls, not the initialization cost.
    group.bench_function("print_cell", |b| {
        let mut core = TerminalCore::new(24, 80);
        b.iter(|| {
            black_box(core.advance(&[b'X']));
            black_box(core.advance(&[b'Y']));
            black_box(core.advance(&[b'Z']));
        });
    });

    group.finish();
}

criterion_group!(benches, bench_ffi_latency);
criterion_main!(benches);
