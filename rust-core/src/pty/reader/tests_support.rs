use std::fs::File;
use std::io::Write as _;
use std::os::unix::io::FromRawFd as _;
use std::sync::atomic::AtomicBool;
use std::sync::mpsc::SyncSender;
use std::sync::Arc;

use super::super::PtyReader;

pub(super) fn make_pipe() -> (File, File) {
    let mut fds = [0i32; 2];
    // SAFETY: fds is a 2-element array; libc::pipe fills it with two valid fds on success.
    let ret = unsafe { libc::pipe(fds.as_mut_ptr()) };
    assert_eq!(ret, 0, "pipe() failed");

    let read_fd = fds[0];
    let write_fd = fds[1];

    // SAFETY: read_fd/write_fd are valid fds from pipe above; File takes ownership.
    let read_file = unsafe { File::from_raw_fd(read_fd) };
    // SAFETY: read_fd/write_fd are valid fds from pipe above; File takes ownership.
    let write_file = unsafe { File::from_raw_fd(write_fd) };
    (read_file, write_file)
}

pub(super) fn spawn_reader(
    read_file: File,
    sender: SyncSender<Vec<u8>>,
    shutdown: Arc<AtomicBool>,
) -> (std::thread::JoinHandle<()>, Arc<AtomicBool>) {
    let process_exited = Arc::new(AtomicBool::new(false));
    let process_exited_clone = Arc::clone(&process_exited);
    let handle = std::thread::spawn(move || {
        PtyReader::read_loop(read_file, sender, shutdown, process_exited_clone);
    });
    (handle, process_exited)
}

pub(super) fn write_all(mut file: File, bytes: &[u8]) {
    file.write_all(bytes).expect("write failed");
}
