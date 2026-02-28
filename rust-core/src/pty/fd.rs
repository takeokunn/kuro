//! Safe file descriptor wrappers with RAII and proper error handling
//!
//! This module provides safe Rust wrappers around unsafe libc file descriptor
//! operations like dup() and dup2(), with automatic cleanup on error paths.

use crate::error::KuroError;
use log::{debug, error, trace};
use std::ffi::CStr;
use std::fmt;
use std::os::unix::io::{AsRawFd, FromRawFd, IntoRawFd, RawFd};

/// A safe wrapper around a raw file descriptor that automatically closes on drop
///
/// This type provides RAII semantics for file descriptors, ensuring that the
/// descriptor is properly closed even if an error occurs. It can be converted
/// to and from std::fs::File using standard traits.
#[derive(Debug)]
pub struct Fd {
    /// The raw file descriptor, or None if it has been closed/consumed
    fd: Option<libc::c_int>,
}

impl Fd {
    /// Create a new Fd from a raw file descriptor
    ///
    /// # Safety
    /// The caller must ensure that `fd` is a valid open file descriptor
    /// that this Fd now owns.
    pub unsafe fn from_raw_fd(fd: libc::c_int) -> Self {
        Self { fd: Some(fd) }
    }

    /// Duplicate a file descriptor using safe_dup()
    ///
    /// This is a convenience wrapper around safe_dup() that returns an Fd.
    ///
    /// # Errors
    /// Returns an error if dup() fails, with errno context.
    pub fn duplicate(fd: libc::c_int) -> Result<Self, KuroError> {
        safe_dup(fd)
    }

    /// Duplicate a file descriptor to a specific target using safe_dup2()
    ///
    /// This is a convenience wrapper around safe_dup2() that returns an Fd.
    ///
    /// # Errors
    /// Returns an error if dup2() fails, with errno context.
    pub fn duplicate_to(src_fd: libc::c_int, target_fd: libc::c_int) -> Result<Self, KuroError> {
        safe_dup2(src_fd, target_fd)
    }

    /// Get the raw file descriptor
    ///
    /// Returns None if the fd has been closed or consumed.
    pub fn raw_fd(&self) -> Option<libc::c_int> {
        self.fd
    }

    /// Close the file descriptor if it's still open
    ///
    /// This method takes ownership of the fd and closes it. If the fd has
    /// already been closed or consumed, this is a no-op.
    ///
    /// # Errors
    /// Returns an error if close() fails, with errno context.
    pub fn close(mut self) -> Result<(), KuroError> {
        if let Some(fd) = self.fd.take() {
            unsafe { close_fd(fd) }?;
        }
        Ok(())
    }

    /// Consume the Fd and return the raw fd without closing it
    ///
    /// This transfers ownership of the fd to the caller. The caller is now
    /// responsible for closing the fd.
    pub fn into_raw_fd(mut self) -> libc::c_int {
        self.fd.take().expect("Fd already consumed")
    }
}

impl AsRawFd for Fd {
    fn as_raw_fd(&self) -> RawFd {
        self.fd.expect("Fd already consumed") as RawFd
    }
}

impl IntoRawFd for Fd {
    fn into_raw_fd(mut self) -> RawFd {
        self.fd.take().expect("Fd already consumed") as RawFd
    }
}

impl Drop for Fd {
    fn drop(&mut self) {
        if let Some(fd) = self.fd.take() {
            // Best-effort close in destructor - we can't panic here
            let result = unsafe { close_fd_unchecked(fd) };
            if let Err(e) = result {
                error!("[Fd] Failed to close fd {} in drop: {}", fd, e);
            }
        }
    }
}

/// RAII guard for a file descriptor that automatically closes when dropped
///
/// Unlike Fd, this is a temporary guard meant for short-lived operations
/// where you need automatic cleanup but don't want full Fd semantics.
#[derive(Debug)]
pub struct FdGuard {
    /// The raw file descriptor being guarded
    fd: Option<libc::c_int>,
}

impl FdGuard {
    /// Create a new guard for a raw file descriptor
    ///
    /// # Safety
    /// The caller must ensure that `fd` is a valid open file descriptor.
    pub unsafe fn new(fd: libc::c_int) -> Self {
        Self { fd: Some(fd) }
    }

    /// Get the raw file descriptor
    pub fn fd(&self) -> Option<libc::c_int> {
        self.fd
    }

    /// Consume the guard and return the fd without closing it
    pub fn into_inner(mut self) -> libc::c_int {
        self.fd.take().expect("FdGuard already consumed")
    }

    /// Close the fd and consume the guard
    pub fn close(mut self) -> Result<(), KuroError> {
        if let Some(fd) = self.fd.take() {
            unsafe { close_fd(fd) }?;
        }
        Ok(())
    }
}

impl Drop for FdGuard {
    fn drop(&mut self) {
        if let Some(fd) = self.fd.take() {
            let result = unsafe { close_fd_unchecked(fd) };
            if let Err(e) = result {
                error!("[FdGuard] Failed to close fd {} in drop: {}", fd, e);
            }
        }
    }
}

/// Safe wrapper around libc::dup()
///
/// Duplicates a file descriptor, returning a new Fd that automatically closes
/// the duplicate on drop.
///
/// # Errors
/// Returns KuroError::Ffi with errno context if dup() fails.
pub fn safe_dup(fd: libc::c_int) -> Result<Fd, KuroError> {
    trace!("[safe_dup] Duplicating fd {}", fd);
    let result = unsafe { libc::dup(fd) };
    if result == -1 {
        let errno = std::io::Error::last_os_error();
        let err_msg = format!("dup(fd={}) failed: {}", fd, errno);
        error!("[safe_dup] {}", err_msg);
        return Err(KuroError::Ffi(err_msg));
    }
    debug!("[safe_dup] Successfully duplicated fd {} to {}", fd, result);
    Ok(unsafe { Fd::from_raw_fd(result) })
}

/// Safe wrapper around libc::dup2()
///
/// Duplicates a file descriptor to a specific target fd. If the target fd
/// is already open, it's closed first. The target fd is then made a copy of
/// the source fd.
///
/// # Errors
/// Returns KuroError::Ffi with errno context if dup2() fails.
pub fn safe_dup2(src_fd: libc::c_int, target_fd: libc::c_int) -> Result<Fd, KuroError> {
    trace!("[safe_dup2] Duplicating fd {} to {}", src_fd, target_fd);
    let result = unsafe { libc::dup2(src_fd, target_fd) };
    if result == -1 {
        let errno = std::io::Error::last_os_error();
        let err_msg = format!("dup2(src={}, target={}) failed: {}", src_fd, target_fd, errno);
        error!("[safe_dup2] {}", err_msg);
        return Err(KuroError::Ffi(err_msg));
    }
    debug!("[safe_dup2] Successfully duplicated fd {} to {}", src_fd, target_fd);
    Ok(unsafe { Fd::from_raw_fd(result) })
}

/// Close a file descriptor with proper error handling
///
/// # Safety
/// The caller must ensure that `fd` is a valid file descriptor that should be closed.
unsafe fn close_fd(fd: libc::c_int) -> Result<(), KuroError> {
    trace!("[close_fd] Closing fd {}", fd);
    let result = libc::close(fd);
    if result == -1 {
        let errno = std::io::Error::last_os_error();
        let err_msg = format!("close(fd={}) failed: {}", fd, errno);
        error!("[close_fd] {}", err_msg);
        return Err(KuroError::Ffi(err_msg));
    }
    debug!("[close_fd] Successfully closed fd {}", fd);
    Ok(())
}

/// Close a file descriptor without panicking on error
///
/// This is used in drop implementations where we can't panic. Errors are
/// logged but not propagated.
///
/// # Safety
/// The caller must ensure that `fd` is a valid file descriptor that should be closed.
unsafe fn close_fd_unchecked(fd: libc::c_int) -> Result<(), String> {
    let result = libc::close(fd);
    if result == -1 {
        let errno = std::io::Error::last_os_error();
        let err_msg = format!("close(fd={}) failed: {}", fd, errno);
        return Err(err_msg);
    }
    Ok(())
}

/// Get the current errno as a string description
///
/// This provides human-readable error messages for errno values.
pub fn errno_description() -> String {
    let errno = std::io::Error::last_os_error();
    errno.to_string()
}

/// Format an error message with errno context
///
/// Helper function to consistently format error messages with errno information.
pub fn format_errno(operation: &str, detail: &str) -> String {
    let errno = std::io::Error::last_os_error();
    format!("{}: {} (errno: {} - {})", operation, detail, errno.raw_os_error().unwrap_or(-1), errno)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs::File;
    use std::io::Write;

    #[test]
    fn test_fd_duplicate_valid() {
        // Create a temporary file
        let mut file = tempfile::NamedTempFile::new().unwrap();
        file.write_all(b"test").unwrap();

        let fd = file.as_raw_fd() as libc::c_int;
        let duplicate = safe_dup(fd);

        assert!(duplicate.is_ok(), "safe_dup should succeed for valid fd");
        let dup_fd = duplicate.unwrap();
        assert!(dup_fd.raw_fd().is_some());

        // Verify the duplicate is a different fd
        assert_ne!(fd, dup_fd.raw_fd().unwrap());
    }

    #[test]
    fn test_fd_duplicate_invalid() {
        // Try to duplicate an invalid fd
        let result = safe_dup(-1);
        assert!(result.is_err(), "safe_dup should fail for invalid fd");
    }

    #[test]
    fn test_fd_dup2_valid() {
        // Create two temporary files
        let file1 = tempfile::NamedTempFile::new().unwrap();
        let file2 = tempfile::NamedTempFile::new().unwrap();

        let src_fd = file1.as_raw_fd() as libc::c_int;
        let target_fd = file2.as_raw_fd() as libc::c_int;

        let result = safe_dup2(src_fd, target_fd);
        assert!(result.is_ok(), "safe_dup2 should succeed for valid fds");
    }

    #[test]
    fn test_fd_dup2_invalid() {
        let result = safe_dup2(-1, 100);
        assert!(result.is_err(), "safe_dup2 should fail for invalid src fd");
    }

    #[test]
    fn test_fd_close_on_drop() {
        // Create a temporary file
        let file = tempfile::NamedTempFile::new().unwrap();
        let fd = file.as_raw_fd() as libc::c_int;

        // Duplicate the fd
        let dup_fd = safe_dup(fd).unwrap();
        let dup_fd_raw = dup_fd.raw_fd().unwrap();

        // Drop the Fd - it should close the fd
        drop(dup_fd);

        // Verify the fd is now closed by trying to close it again
        let result = unsafe { libc::close(dup_fd_raw) };
        assert_eq!(result, -1, "fd should be closed after drop");
    }

    #[test]
    fn test_fd_guard_cleanup() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let fd = file.as_raw_fd() as libc::c_int;

        let dup_fd = safe_dup(fd).unwrap();
        let dup_fd_raw = dup_fd.raw_fd().unwrap();

        // Create a guard - it will close the fd on drop
        let _guard = unsafe { FdGuard::new(dup_fd_raw) };

        // Guard is dropped here, fd should be closed
    }

    #[test]
    fn test_fd_into_raw_fd() {
        let file = tempfile::NamedTempFile::new().unwrap();
        let fd = file.as_raw_fd() as libc::c_int;

        let dup_fd = safe_dup(fd).unwrap();
        let raw = dup_fd.into_raw_fd();

        // Close the raw fd manually
        let result = unsafe { libc::close(raw) };
        assert_eq!(result, 0, "should be able to close the raw fd");
    }

    #[test]
    fn test_errno_description() {
        let desc = errno_description();
        assert!(!desc.is_empty(), "errno description should not be empty");
    }

    #[test]
    fn test_format_errno() {
        // Force an error to get a meaningful errno
        let _ = unsafe { libc::close(-1) };
        let msg = format_errno("test_operation", "test detail");
        assert!(msg.contains("test_operation"), "should contain operation name");
        assert!(msg.contains("test detail"), "should contain detail");
    }
}
