use std::sync::atomic::AtomicBool;
use std::sync::mpsc::sync_channel;
use std::sync::Arc;

use super::tests_support::{make_pipe, spawn_reader, write_all};

#[test]
fn test_reader_receives_data() {
    let (read_file, write_file) = make_pipe();
    let (tx, rx) = sync_channel::<Vec<u8>>(128);
    let shutdown = Arc::new(AtomicBool::new(false));
    let (handle, _process_exited) = spawn_reader(read_file, tx, shutdown);

    write_all(write_file, b"hello");

    let mut received = Vec::new();
    while received.len() < 5 {
        match rx.recv_timeout(std::time::Duration::from_secs(2)) {
            Ok(chunk) => received.extend_from_slice(&chunk),
            Err(_) => break,
        }
    }

    handle.join().expect("reader thread panicked");
    assert_eq!(&received[..], b"hello");
}

/// Verify that setting the shutdown flag before the loop starts causes it to
/// exit immediately without blocking, even when the read end is open.
#[test]
fn test_reader_shutdown_flag_stops_loop() {
    let (read_file, write_file) = make_pipe();
    let (tx, rx) = sync_channel::<Vec<u8>>(128);
    let shutdown = Arc::new(AtomicBool::new(true));
    let (handle, _process_exited) = spawn_reader(read_file, tx, shutdown);

    drop(write_file);

    let finished = handle.join().is_ok();
    assert!(
        finished,
        "reader thread should finish when shutdown flag is set"
    );

    assert!(rx.try_recv().is_err(), "channel should be empty");
}

/// Verify that closing the write end of the pipe causes the `read_loop` to exit
/// (EOF path) and the channel receives no data when nothing was written.
#[test]
fn test_reader_empty_channel_on_eof() {
    let (read_file, write_file) = make_pipe();
    let (tx, rx) = sync_channel::<Vec<u8>>(128);
    let shutdown = Arc::new(AtomicBool::new(false));

    drop(write_file);

    let (handle, _process_exited) = spawn_reader(read_file, tx, shutdown);
    handle.join().expect("reader thread panicked");

    assert!(
        rx.try_recv().is_err(),
        "channel should be empty when pipe write end was closed with no data"
    );
}
