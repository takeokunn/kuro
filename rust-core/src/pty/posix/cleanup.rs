//! Process cleanup helpers for POSIX PTYs.

use nix::sys::signal::{kill, Signal};
use nix::sys::wait::{waitpid, WaitPidFlag};
use nix::unistd::Pid;

/// Maximum time to wait for a child process to exit after SIGHUP before
/// escalating to SIGKILL.
pub(super) const DROP_WAITPID_TIMEOUT_MS: u64 = 1_000;

/// Sleep interval between non-blocking waitpid polls during Pty::drop.
const DROP_WAITPID_POLL_INTERVAL: std::time::Duration = std::time::Duration::from_millis(10);

pub(super) fn signal_child_tree(child_pid: Pid, signal: Signal) {
    // The child calls setsid(), so its pid is also the initial process-group id.
    // Signal both the group and the shell pid: the direct pid covers shells that
    // have already changed groups, while the group reaches foreground children.
    let group = Pid::from_raw(-child_pid.as_raw());
    if let Err(e) = kill(group, signal) {
        // ESRCH means the group already exited. EPERM can happen if a foreground
        // process has moved into a group we cannot signal; the direct child
        // signal below is the authoritative cleanup path for reaping.
        if !matches!(e, nix::errno::Errno::ESRCH | nix::errno::Errno::EPERM) {
            eprintln!("[PTY] Drop: failed to send {signal:?} to {group}: {e}");
        }
    }

    if let Err(e) = kill(child_pid, signal) {
        // ESRCH means the shell process already exited.
        if e != nix::errno::Errno::ESRCH {
            eprintln!("[PTY] Drop: failed to send {signal:?} to {child_pid}: {e}");
        }
    }
}

pub(super) fn reap_child_until(child_pid: Pid, timeout: std::time::Duration) -> bool {
    let poll_ms = DROP_WAITPID_POLL_INTERVAL.as_millis() as u64;
    let max_retries = (timeout.as_millis() as u64 / poll_ms).max(1);

    for _ in 0..max_retries {
        match waitpid(child_pid, Some(WaitPidFlag::WNOHANG)) {
            Ok(nix::sys::wait::WaitStatus::StillAlive) => {
                std::thread::sleep(DROP_WAITPID_POLL_INTERVAL);
            }
            Ok(_) | Err(nix::errno::Errno::ECHILD) => {
                return true;
            }
            Err(e) => {
                eprintln!("[PTY] Drop: waitpid(WNOHANG) failed: {e}");
                return true;
            }
        }
    }

    false
}
