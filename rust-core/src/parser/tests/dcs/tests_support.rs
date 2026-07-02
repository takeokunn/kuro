use crate::parser::dcs::{dcs_hook, dcs_put, dcs_unhook};

/// Build a minimal `vte::Params` with no numeric parameters.
pub(crate) fn empty_params() -> vte::Params {
    vte::Params::default()
}

/// Simulate a complete DCS sequence: hook → put bytes → unhook.
pub(crate) fn run_dcs(core: &mut crate::TerminalCore, intermediates: &[u8], c: char, data: &[u8]) {
    dcs_hook(core, &empty_params(), intermediates, false, c);
    for &byte in data {
        dcs_put(core, byte);
    }
    dcs_unhook(core);
}

/// Collect DCS responses as UTF-8 strings.
pub(crate) fn dcs_response_texts(core: &crate::TerminalCore) -> Vec<&str> {
    core.meta
        .pending_responses
        .iter()
        .map(|resp| std::str::from_utf8(resp).expect("response must be valid UTF-8"))
        .collect()
}

/// Assert that a DCS sequence produced no pending responses.
pub(crate) fn assert_no_dcs_responses(core: &crate::TerminalCore) {
    assert!(
        core.meta.pending_responses.is_empty(),
        "expected no DCS responses, got: {:?}",
        dcs_response_texts(core)
    );
}

/// Assert that DCS responses match the expected prefixes in order.
pub(crate) fn assert_dcs_response_prefixes(responses: &[&str], prefixes: &[&str]) {
    assert_eq!(
        responses.len(),
        prefixes.len(),
        "unexpected DCS response count"
    );

    for (idx, (resp, prefix)) in responses.iter().zip(prefixes.iter()).enumerate() {
        assert!(
            resp.starts_with(prefix),
            "response #{idx} must start with {prefix:?}, got: {resp:?}"
        );
    }
}

/// Assert that a single DCS response starts with the given prefix and contains
/// all expected fragments.
pub(crate) fn assert_single_dcs_response_contains(
    responses: &[&str],
    prefix: &str,
    fragments: &[&str],
) {
    assert_eq!(
        responses.len(),
        1,
        "single-response DCS queries must produce exactly one response"
    );

    let resp = responses[0];
    assert!(
        resp.starts_with(prefix),
        "response must start with {prefix:?}, got: {resp:?}"
    );

    for fragment in fragments {
        assert!(
            resp.contains(fragment),
            "response must contain {fragment:?}, got: {resp:?}"
        );
    }
}

/// Assert the cursor position after a single Sixel placement.
pub(crate) fn assert_single_sixel_notification(core: &crate::TerminalCore, row: usize, col: usize) {
    assert_sixel_notification_count(core, 1);

    let notification = &core.kitty.pending_image_notifications[0];
    assert_eq!(notification.row, row, "unexpected sixel notification row");
    assert_eq!(notification.col, col, "unexpected sixel notification col");
}

/// Assert that a DCS sequence produced the expected number of Sixel image
/// notifications.
pub(crate) fn assert_sixel_notification_count(core: &crate::TerminalCore, count: usize) {
    assert_eq!(
        core.kitty.pending_image_notifications.len(),
        count,
        "unexpected number of sixel image notifications"
    );
}

/// Assert that a DCS sequence produced no pending Sixel image notifications.
pub(crate) fn assert_no_sixel_notifications(core: &crate::TerminalCore) {
    assert_sixel_notification_count(core, 0);
}
