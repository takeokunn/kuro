//! Kitty Graphics Protocol file / temp / shared-memory media transmission.
//!
//! When the Kitty graphics `t=` (transmission) key is `f` (regular file),
//! `t` (temporary file, delete after read), or `s` (POSIX shared memory),
//! the APC payload is **not** the image bytes themselves. Instead it is the
//! base64-encoded absolute file path (for `f`/`t`) or POSIX shm object name
//! (for `s`). This module decodes that reference, validates it against a
//! strict security whitelist, reads the referenced bytes (honoring optional
//! `S=`/`O=` size/offset partial-read keys), and returns the raw image bytes
//! so the caller can feed them through the existing `t=d` (direct) decode path.
//!
//! # Security model (mirrors the OSC 51 / shell whitelist rigor)
//!
//! A PTY is under remote/attacker control. Reading an arbitrary path named by
//! the PTY is a file-disclosure primitive, so every guard below is mandatory:
//!
//! - **Regular files only.** [`std::fs::symlink_metadata`] is used (does NOT
//!   follow symlinks) so a symlink to a device/socket/FIFO is rejected. Only
//!   `is_file()` regular files are accepted.
//! - **No symlinks.** A symlink itself is refused outright — we never traverse
//!   one, closing symlink-to-special and symlink-escape attacks.
//! - **Sensitive prefixes blocked.** Any path under `/proc`, `/sys`, or `/dev`
//!   is refused (e.g. `/proc/self/maps`, `/dev/null`, `/dev/zero`).
//! - **Size cap.** Reads are capped at [`MAX_APC_PAYLOAD_BYTES`] — the same
//!   memory budget as direct/chunked transmission.
//! - **Temp deletion is narrow.** A `t=t` file is deleted only if its path
//!   contains `tty-graphics-protocol` AND resides in a known temp dir
//!   (`/tmp`, `/dev/shm`, or `$TMPDIR`). Otherwise it is read but left intact.
//!
//! On ANY guard failure the command is silently ignored (`None`) — no panic,
//! no partial image.

use crate::parser::kitty::KittyParams;
use crate::parser::limits::MAX_APC_PAYLOAD_BYTES;
use std::path::Path;

/// Substring a path must contain before a `t=t` temp file may be deleted.
const TTY_GRAPHICS_MARKER: &str = "tty-graphics-protocol";

/// Path prefixes that are always refused (kernel/virtual/device filesystems).
const BLOCKED_PREFIXES: [&str; 3] = ["/proc", "/sys", "/dev"];

/// Decode the base64 APC payload into the referenced path / shm name string.
///
/// The decoded bytes must be valid UTF-8 (paths and shm names are text).
fn decode_reference(b64_data: &[u8]) -> Option<String> {
    if b64_data.is_empty() {
        return None;
    }
    let bytes = crate::util::base64::decode(b64_data).ok()?;
    String::from_utf8(bytes).ok()
}

/// Apply the optional `S=` (size) / `O=` (offset) partial-read window to a
/// freshly read byte buffer.
///
/// `O` skips that many leading bytes; `S` truncates to that many bytes. An
/// out-of-range offset yields an empty buffer (caller decides whether empty
/// is acceptable — for image data it will fail dimension checks downstream).
fn apply_window(mut bytes: Vec<u8>, params: &KittyParams) -> Vec<u8> {
    if let Some(offset) = params.read_offset {
        let offset = offset as usize;
        if offset >= bytes.len() {
            return Vec::new();
        }
        bytes.drain(..offset);
    }
    if let Some(size) = params.read_size {
        bytes.truncate(size as usize);
    }
    bytes
}

/// Return `true` if `path` is rooted under any blocked virtual/device prefix.
fn is_blocked_path(path: &Path) -> bool {
    BLOCKED_PREFIXES
        .iter()
        .any(|prefix| path.starts_with(prefix))
}

/// Validate that `path` is a safe, plain regular file (no symlinks, no special
/// files, not under a blocked prefix) and return its size in bytes.
///
/// Uses `symlink_metadata` so a symlink is detected as a symlink (not followed),
/// and rejected. Returns `None` on any guard failure.
fn validate_regular_file(path: &Path) -> Option<u64> {
    // The Kitty protocol mandates absolute paths for t=f/t. Refusing relative
    // paths closes a `../../etc/passwd`-style traversal that would otherwise read
    // files relative to the host Emacs working directory.
    if !path.is_absolute() {
        return None;
    }
    if is_blocked_path(path) {
        return None;
    }
    // symlink_metadata does NOT follow the final symlink, so file_type below
    // reflects the link itself — letting us refuse symlinks outright.
    let meta = std::fs::symlink_metadata(path).ok()?;
    let ft = meta.file_type();
    if ft.is_symlink() || !ft.is_file() {
        return None;
    }
    Some(meta.len())
}

/// Read the bytes referenced by a regular file path, honoring `S=`/`O=` and
/// the global size cap. Returns the raw image bytes, or `None` on any failure.
fn read_regular_file(path: &Path, params: &KittyParams) -> Option<Vec<u8>> {
    let len = validate_regular_file(path)?;
    if len as usize > MAX_APC_PAYLOAD_BYTES {
        return None;
    }
    let bytes = std::fs::read(path).ok()?;
    if bytes.len() > MAX_APC_PAYLOAD_BYTES {
        return None;
    }
    let windowed = apply_window(bytes, params);
    if windowed.len() > MAX_APC_PAYLOAD_BYTES {
        return None;
    }
    Some(windowed)
}

/// Return `true` if a `t=t` temp file at `path` is eligible for deletion:
/// it must contain the `tty-graphics-protocol` marker AND live in a known
/// temp directory (`/tmp`, `/dev/shm`, or `$TMPDIR`).
fn is_deletable_temp(path: &Path) -> bool {
    let Some(path_str) = path.to_str() else {
        return false;
    };
    if !path_str.contains(TTY_GRAPHICS_MARKER) {
        return false;
    }
    let mut temp_dirs = vec!["/tmp".to_string(), "/dev/shm".to_string()];
    if let Ok(tmpdir) = std::env::var("TMPDIR") {
        if !tmpdir.is_empty() {
            temp_dirs.push(tmpdir.trim_end_matches('/').to_string());
        }
    }
    temp_dirs
        .iter()
        .any(|dir| path.starts_with(dir) || path_str.starts_with(dir))
}

/// Read image bytes from a regular file (`t=f`).
pub(super) fn read_file_media(reference: &str, params: &KittyParams) -> Option<Vec<u8>> {
    read_regular_file(Path::new(reference), params)
}

/// Read image bytes from a temp file (`t=t`), deleting it afterward only when
/// the narrow deletion rule permits.
pub(super) fn read_temp_media(reference: &str, params: &KittyParams) -> Option<Vec<u8>> {
    let path = Path::new(reference);
    let bytes = read_regular_file(path, params)?;
    if is_deletable_temp(path) {
        // Best-effort: ignore deletion errors (file may already be gone).
        let _ = std::fs::remove_file(path);
    }
    Some(bytes)
}

/// Read image bytes from a POSIX shared-memory object (`t=s`).
///
/// # Portability / safety note
///
/// `shm_open` is a thin libc wrapper that returns a file descriptor backed by a
/// `tmpfs` object; the `nix` crate in this project is built WITHOUT the `mman`
/// feature, so we use `libc` (already a unix dependency) directly. The fd is
/// wrapped in [`std::fs::File`] via `from_raw_fd` so all reads go through safe
/// std I/O and the fd is closed on drop. We never `shm_unlink` an object we did
/// not create — removing an arbitrary named shm object could destroy another
/// process's data, so deletion is intentionally omitted.
#[cfg(unix)]
pub(super) fn read_shm_media(reference: &str, params: &KittyParams) -> Option<Vec<u8>> {
    use std::ffi::CString;
    use std::io::Read as _;
    use std::os::unix::io::FromRawFd as _;

    // POSIX shm names are a single leading slash followed by up to NAME_MAX
    // non-slash chars. Reject anything with embedded NULs or path traversal.
    if reference.is_empty() || reference.contains('\0') {
        return None;
    }
    let cname = CString::new(reference).ok()?;

    // SAFETY: cname is a valid NUL-terminated C string; O_RDONLY shm_open with
    // mode 0 (ignored without O_CREAT) returns a fd or -1. No memory is shared
    // across the call boundary.
    let fd = unsafe { libc::shm_open(cname.as_ptr(), libc::O_RDONLY, 0) };
    if fd < 0 {
        return None;
    }

    // SAFETY: fd is a valid, freshly-opened descriptor owned exclusively here;
    // File takes ownership and closes it on drop.
    let mut file = unsafe { std::fs::File::from_raw_fd(fd) };

    // Validate it is a regular shm object and within the size cap before reading.
    let len = file.metadata().ok()?.len();
    if len as usize > MAX_APC_PAYLOAD_BYTES {
        return None;
    }

    let mut bytes = Vec::new();
    // Cap the read to avoid unbounded growth if metadata under-reports.
    file.by_ref()
        .take(MAX_APC_PAYLOAD_BYTES as u64 + 1)
        .read_to_end(&mut bytes)
        .ok()?;
    if bytes.len() > MAX_APC_PAYLOAD_BYTES {
        return None;
    }

    let windowed = apply_window(bytes, params);
    if windowed.len() > MAX_APC_PAYLOAD_BYTES {
        return None;
    }
    Some(windowed)
}

/// Non-unix fallback: POSIX shared memory is unavailable; ignore gracefully.
#[cfg(not(unix))]
pub(super) fn read_shm_media(_reference: &str, _params: &KittyParams) -> Option<Vec<u8>> {
    None
}

/// Resolve a non-direct transmission (`t=f`/`t`/`s`) into raw image bytes.
///
/// `b64_data` is the base64-encoded path/name from the APC payload. Returns the
/// referenced bytes (post `S=`/`O=` windowing) on success, or `None` on any
/// guard failure (silently ignored by the caller).
pub(super) fn resolve_media_payload(
    transmission: char,
    b64_data: &[u8],
    params: &KittyParams,
) -> Option<Vec<u8>> {
    let reference = decode_reference(b64_data)?;
    match transmission {
        'f' => read_file_media(&reference, params),
        't' => read_temp_media(&reference, params),
        's' => read_shm_media(&reference, params),
        _ => None,
    }
}

#[cfg(test)]
#[path = "tests/kitty_media.rs"]
mod tests;
