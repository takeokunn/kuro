//! Tests for Kitty graphics file / temp / shared-memory media transmission.
//!
//! Module under test: `parser/kitty_media.rs` (via `parser/kitty.rs`)
//!
//! These tests write real files into [`std::env::temp_dir`] and clean them up.
//! Each test uses a unique filename (PID + counter) to avoid cross-test races.

use crate::parser::kitty::{process_apc_payload, ImageFormat, KittyCommand};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

/// Monotonic counter so concurrent tests never collide on a temp filename.
static COUNTER: AtomicU64 = AtomicU64::new(0);

/// Build a unique temp path under `std::env::temp_dir` with the given stem.
fn unique_temp_path(stem: &str) -> PathBuf {
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    let pid = std::process::id();
    std::env::temp_dir().join(format!("kuro-kitty-{stem}-{pid}-{n}"))
}

/// Run a single (non-chunked) APC payload and return the resulting command.
fn run_once(payload: &[u8]) -> Option<KittyCommand> {
    let mut chunk_state = None;
    process_apc_payload(payload, &mut chunk_state)
}

/// Base64-encode a path string for embedding in an APC payload.
fn b64(s: &str) -> String {
    crate::util::base64::encode(s.as_bytes())
}

/// RAII guard that removes a file on drop so tests never leak temp files.
struct TempFileGuard(PathBuf);
impl Drop for TempFileGuard {
    fn drop(&mut self) {
        let _ = std::fs::remove_file(&self.0);
    }
}

/// INTENT: t=f reads a real regular file written by the test and stores the
/// image with the exact bytes/format/dimensions from the referenced file.
#[test]
fn test_t_f_reads_regular_file_and_stores_image() {
    let path = unique_temp_path("regular");
    // 2x1 RGBA = 8 bytes.
    let pixels = vec![1u8, 2, 3, 4, 5, 6, 7, 8];
    std::fs::write(&path, &pixels).expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=f,f=32,s=2,v=1;{}", b64(path.to_str().unwrap()));
    let cmd = run_once(payload.as_bytes());

    match cmd {
        Some(KittyCommand::Transmit {
            pixels: got,
            format,
            pixel_width,
            pixel_height,
            ..
        }) => {
            assert_eq!(got, pixels, "file bytes must reach the stored image verbatim");
            assert_eq!(format, ImageFormat::Rgba);
            assert_eq!(pixel_width, 2);
            assert_eq!(pixel_height, 1);
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}

/// INTENT: t=f honors S=/O= partial reads — O skips leading bytes, S limits
/// the count, so the stored image is the requested window of the file.
#[test]
fn test_t_f_partial_read_with_size_and_offset() {
    let path = unique_temp_path("partial");
    // 4 pixels of RGBA = 16 bytes; we want pixel index 1..3 (8 bytes) back.
    let mut pixels = Vec::new();
    for i in 0u8..16 {
        pixels.push(i);
    }
    std::fs::write(&path, &pixels).expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    // O=4 (skip first pixel), S=8 (read two pixels) -> bytes 4..12.
    let payload = format!(
        "a=t,t=f,f=32,s=2,v=1,O=4,S=8;{}",
        b64(path.to_str().unwrap())
    );
    let cmd = run_once(payload.as_bytes());

    match cmd {
        Some(KittyCommand::Transmit { pixels: got, .. }) => {
            assert_eq!(got, &pixels[4..12], "S/O must window the file bytes");
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}

/// INTENT: t=f refuses /dev/null (a character device, not a regular file).
#[test]
#[cfg(unix)]
fn test_t_f_refuses_dev_null() {
    let payload = format!("a=t,t=f,f=32,s=1,v=1;{}", b64("/dev/null"));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "/dev/null is a device, must be refused"
    );
}

/// INTENT: t=f refuses paths under /proc (kernel virtual filesystem leak).
#[test]
#[cfg(unix)]
fn test_t_f_refuses_proc_self_maps() {
    let payload = format!("a=t,t=f,f=32,s=1,v=1;{}", b64("/proc/self/maps"));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "/proc/self/maps must be refused"
    );
}

/// INTENT: t=f refuses a FIFO (named pipe) — only regular files are allowed.
#[test]
#[cfg(unix)]
fn test_t_f_refuses_fifo() {
    use std::ffi::CString;
    let path = unique_temp_path("fifo");
    let cpath = CString::new(path.to_str().unwrap()).unwrap();
    // SAFETY: cpath is a valid NUL-terminated path; mkfifo creates a FIFO node.
    let rc = unsafe { libc::mkfifo(cpath.as_ptr(), 0o600) };
    if rc != 0 {
        // FIFO creation unsupported on this platform/dir; skip gracefully.
        return;
    }
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=f,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "a FIFO must be refused (not a regular file)"
    );
}

/// INTENT: t=f refuses a symlink pointing to a special file — symlinks are
/// never followed; the symlink itself is rejected.
#[test]
#[cfg(unix)]
fn test_t_f_refuses_symlink_to_special() {
    let link = unique_temp_path("symlink");
    // Point the symlink at /dev/null (a special file).
    if std::os::unix::fs::symlink("/dev/null", &link).is_err() {
        return; // symlink unsupported; skip
    }
    let _guard = TempFileGuard(link.clone());

    let payload = format!("a=t,t=f,f=32,s=1,v=1;{}", b64(link.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "a symlink (to special) must be refused"
    );
}

/// INTENT: t=f refuses paths under /sys (kernel attribute filesystem leak).
#[test]
#[cfg(unix)]
fn test_t_f_refuses_sys_prefix() {
    let payload = format!("a=t,t=f,f=32,s=1,v=1;{}", b64("/sys/kernel/notes"));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "/sys/* must be refused"
    );
}

/// INTENT: t=f refuses /dev/zero (an infinite character device that would
/// otherwise stream until the cap with attacker-chosen contents).
#[test]
#[cfg(unix)]
fn test_t_f_refuses_dev_zero() {
    let payload = format!("a=t,t=f,f=32,s=1,v=1;{}", b64("/dev/zero"));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "/dev/zero must be refused"
    );
}

/// INTENT (security regression): t=f refuses a relative path. A PTY must not be
/// able to read files relative to the host Emacs CWD via `../../etc/passwd`.
#[test]
#[cfg(unix)]
fn test_t_f_refuses_relative_path_traversal() {
    let payload = format!("a=t,t=f,f=32,s=1,v=1;{}", b64("../../../../etc/passwd"));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "relative/traversal path must be refused (absolute paths only)"
    );
    // Also a bare relative filename.
    let payload2 = format!("a=t,t=f,f=32,s=1,v=1;{}", b64("etc/hosts"));
    assert!(
        run_once(payload2.as_bytes()).is_none(),
        "bare relative path must be refused"
    );
}

/// INTENT (security regression): t=t must delete ONLY tty-graphics-protocol
/// temp files — an arbitrary regular file in the temp dir is read but NEVER
/// deleted, even though the deletion machinery runs for every t=t.
#[test]
fn test_t_t_never_deletes_arbitrary_temp_file() {
    // A normal file in the temp dir WITHOUT the marker substring.
    let path = unique_temp_path("important-user-data");
    std::fs::write(&path, b"\x00\x01\x02\x03").expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    let _ = run_once(payload.as_bytes());
    assert!(
        Path::new(&path).exists(),
        "an arbitrary (unmarked) temp file must survive t=t deletion"
    );
}

/// INTENT (security regression): t=t must not delete a marked file that lives
/// OUTSIDE a known temp directory — both conditions (marker AND temp dir) are
/// required before deletion is permitted.
#[test]
#[cfg(unix)]
fn test_t_t_marked_file_outside_tempdir_not_deleted() {
    // A home-rooted path containing the marker substring but NOT in /tmp etc.
    // We synthesize it under temp_dir's PARENT so it has the marker but lives
    // outside the recognized temp roots. To be robust across platforms we build
    // an absolute path under the current dir's canonical root that still is not
    // a temp dir. Use the test crate's own target-adjacent dir.
    let base = std::env::current_dir().expect("cwd");
    let path = base.join(format!(
        "tty-graphics-protocol-outside-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    if std::fs::write(&path, b"keepme").is_err() {
        return; // not writable here; skip gracefully
    }
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    let _ = run_once(payload.as_bytes());
    assert!(
        Path::new(&path).exists(),
        "marked file outside a temp dir must NOT be deleted"
    );
}

/// INTENT: an oversized partial-read window cannot exceed the cap — even with a
/// legitimate small file, a malformed S= larger than the file is harmless (it
/// just truncates to what exists).
#[test]
fn test_t_f_size_larger_than_file_is_harmless() {
    let path = unique_temp_path("smallfile");
    std::fs::write(&path, &[1u8, 2, 3, 4]).expect("write");
    let _guard = TempFileGuard(path.clone());
    // S=999999 far exceeds the 4-byte file; result is just the 4 bytes.
    let payload = format!(
        "a=t,t=f,f=32,s=1,v=1,S=999999;{}",
        b64(path.to_str().unwrap())
    );
    match run_once(payload.as_bytes()) {
        Some(KittyCommand::Transmit { pixels, .. }) => {
            assert_eq!(pixels, vec![1, 2, 3, 4], "S= beyond EOF truncates to file len");
        }
        other => panic!("expected Transmit, got {other:?}"),
    }
}

/// INTENT: t=t deletes the file after reading ONLY when its name contains the
/// `tty-graphics-protocol` marker and it lives in a known temp dir.
#[test]
fn test_t_t_deletes_marked_temp_file() {
    // Build a path that contains the marker AND lives under temp_dir.
    let path = std::env::temp_dir().join(format!(
        "tty-graphics-protocol-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    let pixels = vec![10u8, 20, 30, 40];
    std::fs::write(&path, &pixels).expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    let cmd = run_once(payload.as_bytes());

    assert!(cmd.is_some(), "marked temp file must still produce an image");
    assert!(
        !Path::new(&path).exists(),
        "marked tty-graphics-protocol temp file must be deleted after read"
    );
}

/// INTENT: t=t does NOT delete a file whose name lacks the marker, even though
/// it is read successfully (narrow deletion rule).
#[test]
fn test_t_t_does_not_delete_unmarked_file() {
    let path = unique_temp_path("unmarked");
    let pixels = vec![9u8, 8, 7, 6];
    std::fs::write(&path, &pixels).expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    let cmd = run_once(payload.as_bytes());

    assert!(cmd.is_some(), "unmarked temp file is still read");
    assert!(
        Path::new(&path).exists(),
        "unmarked temp file must NOT be deleted"
    );
}

/// INTENT: an oversized file (exceeding the APC byte cap) is rejected without
/// reading it into a giant buffer.
#[test]
fn test_t_f_oversized_file_rejected() {
    use crate::parser::limits::MAX_APC_PAYLOAD_BYTES;
    let path = unique_temp_path("oversized");
    // One byte over the cap.
    let big = vec![0u8; MAX_APC_PAYLOAD_BYTES + 1];
    std::fs::write(&path, &big).expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=f,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "file exceeding the size cap must be rejected"
    );
}

/// INTENT: a missing path is ignored (no panic, no command).
#[test]
fn test_t_f_missing_path_ignored() {
    let path = unique_temp_path("does-not-exist");
    // Ensure it does not exist.
    let _ = std::fs::remove_file(&path);
    let payload = format!("a=t,t=f,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "missing file must be ignored"
    );
}

/// INTENT: a malformed (non-base64) media payload is ignored.
#[test]
fn test_t_f_malformed_base64_ignored() {
    // '!' is not a base64 alphabet char.
    let payload = b"a=t,t=f,f=32,s=1,v=1;!!!not-base64!!!";
    assert!(
        run_once(payload).is_none(),
        "non-base64 path payload must be ignored"
    );
}

/// INTENT: an empty media payload (no path) is ignored.
#[test]
fn test_t_f_empty_payload_ignored() {
    let payload = b"a=t,t=f,f=32,s=1,v=1;";
    assert!(
        run_once(payload).is_none(),
        "empty path payload must be ignored"
    );
}

/// INTENT: t=s shared-memory reading round-trips real bytes through shm_open.
/// Creates a POSIX shm object, writes image bytes, then transmits via t=s.
#[test]
#[cfg(unix)]
fn test_t_s_reads_shared_memory() {
    use std::ffi::CString;
    use std::io::Write as _;
    use std::os::unix::io::FromRawFd as _;

    let name = format!(
        "/kuro-kitty-shm-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    );
    let cname = CString::new(name.clone()).unwrap();

    // SAFETY: cname is valid; create-or-open an shm object for writing.
    let fd = unsafe {
        libc::shm_open(
            cname.as_ptr(),
            libc::O_CREAT | libc::O_RDWR,
            0o600 as libc::c_uint,
        )
    };
    if fd < 0 {
        // shm unsupported (e.g. sandbox); skip gracefully.
        return;
    }

    let pixels = vec![100u8, 101, 102, 103];
    {
        // SAFETY: fd is freshly opened and owned here; File closes it on drop.
        let mut f = unsafe { std::fs::File::from_raw_fd(fd) };
        if f.set_len(pixels.len() as u64).is_err() || f.write_all(&pixels).is_err() {
            unsafe {
                libc::shm_unlink(cname.as_ptr());
            }
            return;
        }
    }

    let payload = format!("a=t,t=s,f=32,s=1,v=1;{}", b64(&name));
    let cmd = run_once(payload.as_bytes());

    // Clean up the shm object regardless of outcome.
    // SAFETY: cname is valid; unlink the object we created.
    unsafe {
        libc::shm_unlink(cname.as_ptr());
    }

    match cmd {
        Some(KittyCommand::Transmit { pixels: got, .. }) => {
            assert_eq!(got, pixels, "shm bytes must reach the stored image");
        }
        other => panic!("expected Transmit from shm, got {other:?}"),
    }
}
