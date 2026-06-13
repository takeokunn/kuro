// ─────────────────────────────────────────────────────────────────────────────
// In-band resize notifications (?2048)
// Spec: https://gist.github.com/rockorager/e695fb2924d36b2bcf1fff4a3704bd83
// Report format: CSI 48 ; rows ; cols ; height_px ; width_px t  (pixels 0 here).
// ─────────────────────────────────────────────────────────────────────────────

assert_dec_mode_enable_disable!(
    test_inband_resize_enable,
    test_inband_resize_disable,
    b"\x1b[?2048h",
    b"\x1b[?2048l",
    resize_in_band,
    "In-band resize (2048)"
);

assert_dec_mode_reset_after_ris!(
    test_inband_resize_reset_after_ris,
    b"\x1b[?2048h",
    resize_in_band,
    "In-band resize (2048)"
);

/// Enabling ?2048 MUST immediately emit one report of the current size,
/// per spec ("when first enabled, the terminal MUST send a report").
#[test]
fn test_inband_resize_enable_emits_immediate_report() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h");
    assert_eq!(
        common::read_responses(&term),
        vec!["\x1b[48;24;80;0;0t".to_string()],
        "enabling ?2048 must emit exactly one immediate current-size report"
    );
}

/// After ?2048 is enabled, a resize emits a fresh report carrying the NEW size.
/// The immediate enable-report is emitted first, then the resize report.
#[test]
fn test_inband_resize_reports_new_size_on_resize() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h"); // immediate report: 24x80
    term.resize(30, 100); // resize report: 30x100
    assert_eq!(
        common::read_responses(&term),
        vec![
            "\x1b[48;24;80;0;0t".to_string(),
            "\x1b[48;30;100;0;0t".to_string(),
        ],
        "resize after ?2048 must report the new size in characters"
    );
}

/// A resize WITHOUT ?2048 enabled must NOT emit any in-band report.
#[test]
fn test_resize_without_2048_emits_no_report() {
    let mut term = TerminalCore::new(24, 80);
    term.resize(30, 100);
    assert!(
        common::read_responses(&term).is_empty(),
        "resize without ?2048 must not emit an in-band report"
    );
}

/// Re-enabling ?2048 while already enabled MUST report again (spec: "if the
/// mode is already enabled, the terminal MUST immediately report the current
/// size if an attempt is made to enable the feature").
#[test]
fn test_inband_resize_reenable_reports_again() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h\x1b[?2048h");
    assert_eq!(
        common::read_responses(&term),
        vec![
            "\x1b[48;24;80;0;0t".to_string(),
            "\x1b[48;24;80;0;0t".to_string(),
        ],
        "re-enabling ?2048 must emit another immediate report"
    );
}

/// DECRQM (CSI ? 2048 $ p) must report the mode as supported (status 1 = set
/// after enable), which is how clients detect in-band resize support.
#[test]
fn test_inband_resize_decrqm_reports_supported() {
    let mut term = TerminalCore::new(24, 80);
    term.advance(b"\x1b[?2048h"); // also pushes the immediate size report
    term.advance(b"\x1b[?2048$p"); // DECRQM query
    let responses = common::read_responses(&term);
    assert!(
        responses
            .iter()
            .any(|r| r.contains("2048") && r.contains("$y")),
        "DECRQM for enabled ?2048 must report it supported (CSI ? 2048 ; 1 $ y), got: {responses:?}"
    );
}
