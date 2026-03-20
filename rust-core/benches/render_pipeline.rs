//! Benchmarks for the render pipeline: `encode_line` and `get_dirty_lines_with_faces`.
//!
//! These benchmarks establish baselines for the cmatrix-scenario performance fix.
//! Run with: cargo bench --bench `render_pipeline`

use criterion::{black_box, criterion_group, criterion_main, Criterion, Throughput};
use kuro_core::ffi::codec::encode_line;
use kuro_core::grid::screen::Screen;
use kuro_core::types::cell::{Cell, SgrAttributes};
use kuro_core::types::color::Color;

/// Build a line of `n` cells where every cell has a distinct RGB color.
/// This is worst-case for `encode_line`: maximally fragmented face ranges.
fn make_colored_line(n: usize) -> Vec<Cell> {
    (0..n)
        .map(|i| {
            let r = ((i * 7) % 256) as u8;
            let g = ((i * 13) % 256) as u8;
            let b = ((i * 17) % 256) as u8;
            let attrs = SgrAttributes {
                foreground: Color::Rgb(r, g, b),
                ..SgrAttributes::default()
            };
            Cell::with_attrs(char::from_u32(0x41 + (i % 26) as u32).unwrap_or('A'), attrs)
        })
        .collect()
}

/// Build a line of `n` cells with plain ASCII and default attributes.
fn make_plain_line(n: usize) -> Vec<Cell> {
    (0..n)
        .map(|i| Cell::new(char::from_u32(0x41 + (i % 26) as u32).unwrap_or('A')))
        .collect()
}

fn bench_encode_line_colored_80(c: &mut Criterion) {
    let line = make_colored_line(80);
    let cell_count = line.len() as u64;

    let mut group = c.benchmark_group("encode_line");
    group.throughput(Throughput::Elements(cell_count));

    group.bench_function("colored_80", |b| {
        b.iter(|| encode_line(black_box(&line)));
    });

    group.finish();
}

fn bench_encode_line_plain_80(c: &mut Criterion) {
    let line = make_plain_line(80);
    let cell_count = line.len() as u64;

    let mut group = c.benchmark_group("encode_line");
    group.throughput(Throughput::Elements(cell_count));

    group.bench_function("plain_80", |b| {
        b.iter(|| encode_line(black_box(&line)));
    });

    group.finish();
}

fn bench_get_dirty_lines_full_24x80(c: &mut Criterion) {
    let rows = 24u16;
    let cols = 80u16;

    let mut group = c.benchmark_group("get_dirty_lines_with_faces");
    group.throughput(Throughput::Elements(u64::from(rows) * u64::from(cols)));

    group.bench_function("full_screen_24x80", |b| {
        b.iter_batched(
            || {
                // Setup: create a screen with all rows filled and dirty
                let mut screen = Screen::new(rows, cols);
                for row in 0..rows as usize {
                    screen.move_cursor(row, 0);
                    for i in 0..cols as usize {
                        let r = ((row * 7 + i) % 256) as u8;
                        let g = ((row * 13 + i) % 256) as u8;
                        let attrs = SgrAttributes {
                            foreground: Color::Rgb(r, g, 42),
                            ..SgrAttributes::default()
                        };
                        screen.print(
                            char::from_u32(0x41 + (i % 26) as u32).unwrap_or('A'),
                            attrs,
                            false,
                        );
                    }
                }
                // mark_all_dirty after fill (print already marks lines dirty,
                // but be explicit to simulate a cmatrix full-screen repaint)
                screen.mark_all_dirty();
                screen
            },
            |mut screen| {
                // Measure: drain all dirty lines and encode each one
                let dirty = screen.take_dirty_lines();
                for row in dirty {
                    if let Some(line) = screen.get_line(row) {
                        black_box(encode_line(&line.cells));
                    }
                }
            },
            criterion::BatchSize::SmallInput,
        );
    });

    group.finish();
}

fn bench_get_dirty_lines_sparse(c: &mut Criterion) {
    let rows = 24u16;
    let cols = 80u16;

    let mut group = c.benchmark_group("get_dirty_lines_with_faces");
    group.throughput(Throughput::Elements(3 * u64::from(cols)));

    group.bench_function("sparse_3_rows", |b| {
        b.iter_batched(
            || {
                let mut screen = Screen::new(rows, cols);
                // Drain any dirty state from construction
                screen.take_dirty_lines();
                // Mark only 3 rows dirty (typical shell prompt output)
                screen.mark_line_dirty(0);
                screen.mark_line_dirty(1);
                screen.mark_line_dirty(23);
                screen
            },
            |mut screen| {
                let dirty = screen.take_dirty_lines();
                for row in dirty {
                    if let Some(line) = screen.get_line(row) {
                        black_box(encode_line(&line.cells));
                    }
                }
            },
            criterion::BatchSize::SmallInput,
        );
    });

    group.finish();
}

criterion_group!(
    benches,
    bench_encode_line_colored_80,
    bench_encode_line_plain_80,
    bench_get_dirty_lines_full_24x80,
    bench_get_dirty_lines_sparse,
);
criterion_main!(benches);
