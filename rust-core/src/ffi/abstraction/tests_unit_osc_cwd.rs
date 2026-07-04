use super::support::{advance, make_osc_session, osc7};

#[test]
fn test_take_cwd_if_dirty_strips_hostname_prefix() {
    let mut session = make_osc_session();

    advance(&mut session, &osc7("file://myhost/tmp/work"));

    let result = session.take_cwd_if_dirty();
    assert!(result.is_some());

    let path = result.unwrap();
    assert!(path.starts_with('/'));
    assert!(path.contains("tmp") || path.contains("work"));
}

#[test]
fn test_get_cwd_host_none_on_fresh_session() {
    let session = make_osc_session();
    assert!(session.get_cwd_host().is_none());
}

#[test]
fn test_get_cwd_host_returns_hostname_after_osc7() {
    let mut session = make_osc_session();

    advance(&mut session, &osc7("file://remotehost/tmp"));

    let host = session.get_cwd_host();
    assert_eq!(host.as_deref(), Some("remotehost"));
}

#[test]
fn test_get_cwd_host_is_non_destructive() {
    let mut session = make_osc_session();

    advance(&mut session, &osc7("file://myhost/home"));

    let first = session.get_cwd_host();
    let second = session.get_cwd_host();
    assert_eq!(first, second);
}
