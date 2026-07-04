use super::support::{advance, make_osc_session, osc8};

#[test]
fn test_get_hyperlink_ranges_empty_on_fresh_terminal() {
    let session = make_osc_session();
    let ranges = session.get_hyperlink_ranges();
    assert!(ranges.is_empty());
}

#[test]
fn test_get_hyperlink_ranges_single_link_on_row_0() {
    let mut session = make_osc_session();

    advance(&mut session, &osc8("https://example.com", "abc"));

    let ranges = session.get_hyperlink_ranges();
    assert!(!ranges.is_empty());

    let (row, _start, _end, uri) = &ranges[0];
    assert_eq!(*row, 0);
    assert!(uri.contains("example.com"));
}

#[test]
fn test_get_hyperlink_ranges_start_less_than_end() {
    let mut session = make_osc_session();

    advance(&mut session, &osc8("https://test.invalid", "hello"));

    let ranges = session.get_hyperlink_ranges();
    assert!(!ranges.is_empty());

    for (_, start, end, _) in &ranges {
        assert!(end > start);
    }
}
