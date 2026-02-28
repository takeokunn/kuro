//! Core type definitions

pub mod cell;
pub mod color;
pub mod cursor;

// Re-exports
pub use cell::{Cell, CellWidth, SgrAttributes};
pub use color::{Color, NamedColor};
pub use cursor::{Cursor, CursorShape};
