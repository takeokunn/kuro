use super::super::{make_session, TERMINAL_SESSIONS};

pub(crate) fn insert_bound_session(id: u64) {
    let session = make_session(); // state: SessionState::Bound
    TERMINAL_SESSIONS.lock().unwrap().insert(id, session);
}

pub(crate) fn insert_detached_session(id: u64) {
    let mut session = make_session();
    session.set_detached();
    TERMINAL_SESSIONS.lock().unwrap().insert(id, session);
}
