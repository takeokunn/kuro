/// Collect APC responses as UTF-8 strings.
fn apc_response_texts<'a>(core: &'a crate::TerminalCore) -> Vec<&'a str> {
    core.meta
        .pending_responses
        .iter()
        .map(|resp| std::str::from_utf8(resp).expect("response must be valid UTF-8"))
        .collect()
}

/// Assert that an APC sequence produced no pending responses.
pub fn assert_no_apc_responses(core: &crate::TerminalCore) {
    assert!(
        core.meta.pending_responses.is_empty(),
        "expected no APC responses, got: {:?}",
        apc_response_texts(core)
    );
}

/// Assert that an APC sequence produced exactly one pending response and
/// return it as UTF-8 text.
pub fn single_apc_response_text<'a>(core: &'a crate::TerminalCore) -> &'a str {
    assert_eq!(
        core.meta.pending_responses.len(),
        1,
        "expected exactly one APC response"
    );

    std::str::from_utf8(&core.meta.pending_responses[0]).expect("response must be valid UTF-8")
}

/// Assert that a sequence produced the expected number of image notifications.
pub fn assert_pending_image_notification_count(core: &crate::TerminalCore, count: usize) {
    assert_eq!(
        core.kitty.pending_image_notifications.len(),
        count,
        "unexpected number of APC image notifications"
    );
}

/// Assert that no pending image notifications were produced.
pub fn assert_no_pending_image_notifications(core: &crate::TerminalCore) {
    assert_pending_image_notification_count(core, 0);
}

/// Assert that a single pending image notification matches the expected size.
pub fn assert_single_pending_image_notification(
    core: &crate::TerminalCore,
    image_id: u32,
    cell_width: u32,
    cell_height: u32,
) {
    assert_pending_image_notification_count(core, 1);

    let notif = &core.kitty.pending_image_notifications[0];
    assert_eq!(notif.image_id, image_id);
    assert_eq!(notif.cell_width, cell_width);
    assert_eq!(notif.cell_height, cell_height);
}
