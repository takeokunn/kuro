// DECRQSS (DCS $ q <setting> ST) — Request Status String.
//
// `handle_decrqss` has 4 branches; none were previously covered:
//   1. b" q"  → DECSCUSR cursor style
//   2. b"r"   → DECSTBM scroll margins
//   3. b"m"   → current SGR rendition
//   4. unknown → failure prefix DCS 0 $ r ST

use super::*;

/// Run a DECRQSS DCS sequence and assert a single response with the expected
/// prefix and fragments.
macro_rules! test_decrqss_response {
    ($name:ident, setup $setup:expr, payload $payload:expr, prefix $prefix:expr $(, contains $fragment:expr )* $(,)?) => {
        #[test]
        fn $name() {
            let mut core = crate::TerminalCore::new(24, 80);
            ($setup)(&mut core);
            run_dcs(&mut core, b"$", 'q', $payload);
            let responses = dcs_response_texts(&core);
            assert_single_dcs_response_contains(&responses, $prefix, &[$($fragment),*]);
        }
    };
    ($name:ident, setup $setup:expr, payload $payload:expr, prefix $prefix:expr, check $check:expr $(,)?) => {
        #[test]
        fn $name() {
            let mut core = crate::TerminalCore::new(24, 80);
            ($setup)(&mut core);
            run_dcs(&mut core, b"$", 'q', $payload);
            let responses = dcs_response_texts(&core);
            assert_single_dcs_response_contains(&responses, $prefix, &[]);
            ($check)(responses[0]);
        }
    };
}

test_decrqss_response!(
    test_decrqss_cursor_style_default,
    setup |_| {},
    payload b" q",
    prefix "\x1bP1$r",
    contains "0 q",
    contains " q\x1b\\"
);

test_decrqss_response!(
    test_decrqss_cursor_style_after_decscusr,
    setup |core: &mut crate::TerminalCore| {
        core.advance(b"\x1b[6 q");
    },
    payload b" q",
    prefix "\x1bP1$r",
    contains "6 q"
);

test_decrqss_response!(
    test_decrqss_scroll_margins_default,
    setup |_| {},
    payload b"r",
    prefix "\x1bP1$r",
    contains "1;24r"
);

test_decrqss_response!(
    test_decrqss_scroll_margins_after_decstbm,
    setup |core: &mut crate::TerminalCore| {
        core.advance(b"\x1b[5;20r");
    },
    payload b"r",
    prefix "\x1bP1$r",
    contains "5;20r"
);

test_decrqss_response!(
    test_decrqss_sgr_default_attrs,
    setup |_| {},
    payload b"m",
    prefix "\x1bP1$r0m"
);

test_decrqss_response!(
    test_decrqss_sgr_bold_attr,
    setup |core: &mut crate::TerminalCore| {
        core.advance(b"\x1b[1m");
    },
    payload b"m",
    prefix "\x1bP1$r",
    check |resp: &str| {
        assert!(
            resp.contains(";1m") || resp.contains(";1;"),
            "bold must appear as ';1' in the SGR serialisation, got: {resp:?}"
        );
    }
);

test_decrqss_response!(
    test_decrqss_unknown_target_returns_failure,
    setup |_| {},
    payload b"UNKNOWN",
    prefix "\x1bP0$r"
);
