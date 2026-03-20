//! Grid operations benchmark (FR-005-02 and FR-005-03)
//!
//! Measures:
//! - Time to update grid cells (target: >1M cells/s)
//! - Time to erase lines (target: <1ms per line)
#![expect(clippy::cast_possible_truncation, reason = "bench dimension casts: rows/cols are small constants (≤ 400); usize→u16 is always safe here")]

use criterion::{black_box, criterion_group, criterion_main, Criterion, Throughput};
use kuro_core::{grid::screen::Screen, types::cell::SgrAttributes};

/// Benchmark grid cell updates with varying dimensions
fn bench_grid_update(c: &mut Criterion) {
    let mut group = c.benchmark_group("grid_update");

    // Test with different grid sizes: 24x80, 50x200, 100x400
    let sizes = [(24usize, 80usize), (50, 200), (100, 400)];

    for &(rows, cols) in &sizes {
        let cell_count = rows * cols;

        group.throughput(Throughput::Elements(cell_count as u64));

        let input = (rows, cols);
        group.bench_with_input(format!("{rows}x{cols}"), &input, |b, &(rows, cols)| {
            let mut screen = Screen::new(rows as u16, cols as u16);
            let attrs = SgrAttributes::default();

            b.iter(|| {
                // Fill the entire screen with characters
                for row in 0..rows {
                    for _col in 0..cols {
                        screen.print(black_box('A'), attrs, false);
                    }
                    // Return to start of line for next row
                    screen.move_cursor(row, 0);
                }
            });
        });
    }

    group.finish();
}

/// Benchmark screen erase operations
fn bench_screen_erase(c: &mut Criterion) {
    let mut group = c.benchmark_group("screen_erase");

    let sizes = [(24usize, 80usize), (50, 200), (100, 400)];

    for &(rows, cols) in &sizes {
        let input = (rows, cols);
        group.bench_with_input(format!("{rows}x{cols}"), &input, |b, &(rows, cols)| {
            b.iter(|| {
                let mut screen = Screen::new(rows as u16, cols as u16);

                // Fill screen with content
                let attrs = SgrAttributes::default();
                for row in 0..rows {
                    for _col in 0..cols {
                        screen.print('X', attrs, false);
                    }
                    screen.move_cursor(row, 0);
                }

                // Erase all lines
                screen.clear_lines(0, rows);
            });
        });
    }

    group.finish();
}

/// Benchmark single line erase operations
fn bench_line_erase(c: &mut Criterion) {
    let mut group = c.benchmark_group("line_erase");

    group.bench_function("erase_single_line", |b| {
        let mut screen = Screen::new(24, 80);
        let attrs = SgrAttributes::default();

        b.iter(|| {
            // Fill a line with content
            for _col in 0..80 {
                screen.print(black_box('A'), attrs, false);
            }

            // Erase the line
            screen.clear_lines(0, 1);

            // Reset cursor for next iteration
            screen.move_cursor(0, 0);
        });
    });

    group.finish();
}

criterion_group!(
    benches,
    bench_grid_update,
    bench_screen_erase,
    bench_line_erase
);
criterion_main!(benches);
