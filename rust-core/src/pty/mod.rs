//! PTY (Pseudo-Terminal) management

#[cfg(unix)]
pub mod posix;
pub mod reader;

pub use reader::PtyReader;

#[cfg(unix)]
pub use posix::Pty;
