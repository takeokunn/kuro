//! Core type definitions

pub mod cell;
pub mod color;
pub mod cursor;
pub mod kitty;
pub mod meta;
pub mod osc;

// Re-exports
pub use cell::{Cell, CellWidth, SgrAttributes};
pub use color::{Color, NamedColor};
pub use cursor::{Cursor, CursorShape};
pub(crate) use kitty::KittyState;
pub(crate) use meta::TerminalMeta;
