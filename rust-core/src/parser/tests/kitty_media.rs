//! Tests for Kitty graphics file / temp / shared-memory media transmission.
//!
//! Module under test: `parser/kitty_media.rs` (via `parser/kitty.rs`)
//!
//! These tests write real files into [`std::env::temp_dir`] and clean them up.
//! Each test uses a unique filename (PID + counter) to avoid cross-test races.

use crate::parser::kitty::{process_apc_payload, KittyCommand};
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

/// Build a unique temp path using the legacy kitty temp-media marker.
fn unique_marked_temp_path() -> PathBuf {
    let n = COUNTER.fetch_add(1, Ordering::Relaxed);
    let pid = std::process::id();
    std::env::temp_dir().join(format!("tty-graphics-protocol-{pid}-{n}"))
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

/// RAII guard that removes a directory tree on drop.
struct TempDirGuard(PathBuf);
impl Drop for TempDirGuard {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// INTENT: t=f is a host-file disclosure primitive and is refused outright,
/// even for a small regular file owned by the test.
#[test]
fn test_t_f_refuses_regular_file_path() {
    let path = unique_temp_path("regular");
    std::fs::write(path.as_path(), [1u8, 2, 3, 4]).expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=f,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "t=f must never read host filesystem paths"
    );
    assert!(Path::new(&path).exists(), "refused t=f file is untouched");
}

/// INTENT: t=t is refused even for a marked temp-media file with S=/O=.
/// Kuro does not decode or read PTY-provided host path references.
#[test]
fn test_t_t_partial_read_reference_refused_and_preserved() {
    let path = unique_marked_temp_path();
    // 4 pixels of RGBA = 16 bytes; legacy implementations could window this.
    let mut pixels = Vec::new();
    for i in 0u8..16 {
        pixels.push(i);
    }
    std::fs::write(path.as_path(), &pixels).expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    // O=4 and S=8 would window legacy file reads, but no read is attempted.
    let payload = format!(
        "a=t,t=t,f=32,s=2,v=1,O=4,S=8;{}",
        b64(path.to_str().unwrap())
    );
    let cmd = run_once(payload.as_bytes());

    assert!(cmd.is_none(), "t=t host path reference must be refused");
    assert!(
        Path::new(&path).exists(),
        "refused t=t temp file must be preserved"
    );
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

/// INTENT: t=f refuses a FIFO (named pipe). Host paths are never opened.
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
        "relative/traversal path must be refused"
    );
    // Also a bare relative filename.
    let payload2 = format!("a=t,t=f,f=32,s=1,v=1;{}", b64("etc/hosts"));
    assert!(
        run_once(payload2.as_bytes()).is_none(),
        "bare relative path must be refused"
    );
}

/// INTENT (security regression): t=t refuses arbitrary temp files. A file in
/// temp without the legacy marker is neither read nor deleted.
#[test]
fn test_t_t_refuses_arbitrary_temp_file_and_preserves() {
    // A normal file in the temp dir WITHOUT the marker substring.
    let path = unique_temp_path("important-user-data");
    std::fs::write(path.as_path(), b"\x00\x01\x02\x03").expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "unmarked temp file must not be read"
    );
    assert!(
        Path::new(&path).exists(),
        "an arbitrary unmarked temp file must survive t=t handling"
    );
}

/// INTENT (security regression): t=t refuses and preserves a marked file that
/// lives outside a known temp directory.
#[test]
#[cfg(unix)]
fn test_t_t_refuses_marked_file_outside_tempdir_and_preserves() {
    // A current-dir path containing the marker substring but NOT in /tmp etc.
    let base = std::env::current_dir().expect("cwd");
    let path = base.join(format!(
        "tty-graphics-protocol-outside-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    if std::fs::write(path.as_path(), b"keepme").is_err() {
        return; // not writable here; skip gracefully
    }
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "marked file outside a temp dir must not be read"
    );
    assert!(
        Path::new(&path).exists(),
        "marked file outside a temp dir must NOT be deleted"
    );
}

/// INTENT: S= cannot force a host-file read. Even a marked temp-media path with
/// an oversized read window is refused and preserved.
#[test]
fn test_t_t_size_larger_than_file_refused_and_preserved() {
    let path = unique_marked_temp_path();
    std::fs::write(path.as_path(), [1u8, 2, 3, 4]).expect("write");
    let _guard = TempFileGuard(path.clone());
    // S=999999 far exceeds the 4-byte file; no read is attempted.
    let payload = format!(
        "a=t,t=t,f=32,s=1,v=1,S=999999;{}",
        b64(path.to_str().unwrap())
    );
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "t=t host path reference must be refused"
    );
    assert!(
        Path::new(&path).exists(),
        "refused t=t temp file must be preserved"
    );
}

/// INTENT: t=t refuses even a marked file in a known temp dir. No host path is
/// read and no file is deleted.
#[test]
fn test_t_t_marked_temp_file_refused_and_preserved() {
    let path = unique_marked_temp_path();
    let pixels = vec![10u8, 20, 30, 40];
    std::fs::write(path.as_path(), &pixels).expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    let cmd = run_once(payload.as_bytes());

    assert!(cmd.is_none(), "t=t host path reference must be refused");
    assert!(
        Path::new(&path).exists(),
        "marked tty-graphics-protocol temp file must be preserved"
    );
}

/// INTENT: t=t refuses and preserves a file whose name lacks the legacy marker.
#[test]
fn test_t_t_refuses_unmarked_file_and_preserves() {
    let path = unique_temp_path("unmarked");
    std::fs::write(path.as_path(), [9u8, 8, 7, 6]).expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    let cmd = run_once(payload.as_bytes());

    assert!(cmd.is_none(), "unmarked temp file is refused");
    assert!(
        Path::new(&path).exists(),
        "unmarked temp file must NOT be deleted"
    );
}

/// INTENT: an oversized file (exceeding the APC byte cap) is rejected without
/// reading it into a giant buffer.
#[test]
fn test_t_t_oversized_file_rejected_and_preserved() {
    use crate::parser::limits::MAX_APC_PAYLOAD_BYTES;
    let path = unique_marked_temp_path();
    // One byte over the cap.
    let big = vec![0u8; MAX_APC_PAYLOAD_BYTES + 1];
    std::fs::write(path.as_path(), &big).expect("write temp file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "temp file exceeding the size cap must be rejected"
    );
    assert!(
        Path::new(&path).exists(),
        "oversized temp file was not consumed and must be preserved"
    );
}

/// INTENT (security regression): paths that resemble temp roots are still
/// refused and preserved.
#[test]
fn test_t_t_refuses_temp_prefix_confusion_path_and_preserves() {
    let temp_dir = std::env::temp_dir();
    let Some(parent) = temp_dir.parent() else {
        return;
    };
    let Some(temp_name) = temp_dir.file_name().and_then(|name| name.to_str()) else {
        return;
    };
    let sibling = parent.join(format!(
        "{temp_name}-evil-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    if std::fs::create_dir(&sibling).is_err() {
        return;
    }
    let _dir_guard = TempDirGuard(sibling.clone());
    let path = sibling.join(format!(
        "tty-graphics-protocol-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::write(path.as_path(), b"\x00\x01\x02\x03").expect("write prefix-confusion file");
    let _guard = TempFileGuard(path.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "sibling path that only string-prefixes a temp root must be refused"
    );
    assert!(
        Path::new(&path).exists(),
        "refused prefix-confusion file must not be deleted"
    );
}

/// INTENT (security regression): even a marked temp path is refused when the
/// final component is a symlink.
#[test]
#[cfg(unix)]
fn test_t_t_refuses_marked_symlink() {
    let target = unique_temp_path("symlink-target");
    std::fs::write(target.as_path(), b"\x01\x02\x03\x04").expect("write symlink target");
    let _target_guard = TempFileGuard(target.clone());

    let link = unique_marked_temp_path();
    if std::os::unix::fs::symlink(&target, &link).is_err() {
        return;
    }
    let _link_guard = TempFileGuard(link.clone());

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(link.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "marked temp symlink must be refused"
    );
    assert!(Path::new(&link).exists(), "refused symlink must survive");
    assert!(Path::new(&target).exists(), "symlink target must survive");
}

/// INTENT (security regression): t=t refuses marked files reached through a
/// symlinked ancestor directory.
#[test]
#[cfg(unix)]
fn test_t_t_refuses_symlinked_temp_ancestor() {
    let outside = unique_temp_path("ancestor-target-dir");
    if std::fs::create_dir(&outside).is_err() {
        return;
    }
    let _outside_guard = TempDirGuard(outside.clone());

    let link = unique_temp_path("ancestor-link");
    if std::os::unix::fs::symlink(&outside, &link).is_err() {
        return;
    }
    let _link_guard = TempFileGuard(link.clone());

    let path = link.join(format!(
        "tty-graphics-protocol-{}-{}",
        std::process::id(),
        COUNTER.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::write(path.as_path(), b"\x05\x06\x07\x08").expect("write through ancestor symlink");

    let payload = format!("a=t,t=t,f=32,s=1,v=1;{}", b64(path.to_str().unwrap()));
    assert!(
        run_once(payload.as_bytes()).is_none(),
        "marked file under a symlinked temp ancestor must be refused"
    );
    assert!(
        Path::new(&path).exists(),
        "refused ancestor-symlink target file must survive"
    );
}

/// INTENT: a t=f reference to a missing path is ignored (no panic, no command).
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

/// INTENT: a malformed (non-base64) media reference is ignored.
#[test]
fn test_t_f_malformed_base64_ignored() {
    // '!' is not a base64 alphabet char.
    let payload = b"a=t,t=f,f=32,s=1,v=1;!!!not-base64!!!";
    assert!(
        run_once(payload).is_none(),
        "non-base64 path payload must be ignored"
    );
}

/// INTENT: an empty media reference is ignored.
#[test]
fn test_t_f_empty_payload_ignored() {
    let payload = b"a=t,t=f,f=32,s=1,v=1;";
    assert!(
        run_once(payload).is_none(),
        "empty path payload must be ignored"
    );
}

/// INTENT: t=s is refused even when the named POSIX shm object exists.
#[test]
#[cfg(unix)]
fn test_t_s_refuses_shared_memory_reference() {
    use std::ffi::CString;

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
    // SAFETY: fd was returned by shm_open and is owned here.
    if unsafe { libc::close(fd) } != 0 {
        // SAFETY: cname is valid; unlink the object we created before skipping.
        unsafe {
            libc::shm_unlink(cname.as_ptr());
        }
        return;
    }

    let payload = format!("a=t,t=s,f=32,s=1,v=1;{}", b64(&name));
    let cmd = run_once(payload.as_bytes());

    // Clean up the shm object regardless of outcome.
    // SAFETY: cname is valid; unlink the object we created.
    unsafe {
        libc::shm_unlink(cname.as_ptr());
    }

    assert!(
        cmd.is_none(),
        "t=s must not read a host shared-memory object named by the PTY"
    );
}
