// -------------------------------------------------------------------------
// build_xtgettcap_response unit tests (pure lookup, no TerminalCore needed)
// -------------------------------------------------------------------------

use super::*;

/// Test `build_xtgettcap_response` for a known capability: assert that the
/// response starts with the DCS success prefix and (optionally) contains a
/// specific substring.
///
/// Forms:
/// ```text
/// test_build_response!(fn_name, name, hex => success)
/// test_build_response!(fn_name, name, hex => success contains "needle")
/// test_build_response!(fn_name, name, hex => failure)
/// ```
macro_rules! test_build_response {
    ($fn_name:ident, $name:expr, $hex:expr => success) => {
        #[test]
        fn $fn_name() {
            let resp = build_xtgettcap_response($name, $hex);
            assert!(
                resp.starts_with("\x1bP1+r"),
                "{} must produce a success response, got: {resp:?}",
                $name
            );
        }
    };
    ($fn_name:ident, $name:expr, $hex:expr => success contains $needle:expr) => {
        #[test]
        fn $fn_name() {
            let resp = build_xtgettcap_response($name, $hex);
            assert!(
                resp.starts_with("\x1bP1+r"),
                "{} must produce a success response, got: {resp:?}",
                $name
            );
            assert!(
                resp.contains($needle),
                "{} response must contain {:?}, got: {resp:?}",
                $name,
                $needle
            );
        }
    };
    ($fn_name:ident, $name:expr, $hex:expr => failure) => {
        #[test]
        fn $fn_name() {
            let resp = build_xtgettcap_response($name, $hex);
            assert!(
                resp.starts_with("\x1bP0+r"),
                "{} must produce a failure response, got: {resp:?}",
                $name
            );
        }
    };
}

test_build_response!(
    build_xtgettcap_response_tn_starts_with_success_prefix,
    "TN", "544e" => success contains "544e"
);

#[test]
fn build_xtgettcap_response_name_alias_same_as_tn() {
    let resp_tn = build_xtgettcap_response("TN", "544e");
    let resp_name = build_xtgettcap_response("name", "6e616d65");
    // Both must produce success responses (same match arm)
    assert!(resp_tn.starts_with("\x1bP1+r"));
    assert!(resp_name.starts_with("\x1bP1+r"));
}

#[test]
fn build_xtgettcap_response_rgb_encodes_888() {
    let resp = build_xtgettcap_response("RGB", "524742");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "RGB must succeed, got: {resp:?}"
    );
    // "8:8:8" hex-encoded is "383a383a38"
    let expected_val = {
        let mut s = String::new();
        for b in b"8:8:8" {
            use std::fmt::Write as _;
            let _ = write!(s, "{b:02x}");
        }
        s
    };
    assert!(
        resp.contains(&expected_val),
        "RGB response must contain hex-encoded '8:8:8', got: {resp:?}"
    );
}

#[test]
fn build_xtgettcap_response_tc_empty_value() {
    let resp = build_xtgettcap_response("Tc", "5463");
    assert!(
        resp.starts_with("\x1bP1+r"),
        "Tc must succeed, got: {resp:?}"
    );
    // The value part is empty: "...5463=\x1b\\"
    assert!(
        resp.contains("5463=\x1b\\"),
        "Tc response value must be empty, got: {resp:?}"
    );
}

test_build_response!(
    build_xtgettcap_response_colors_encodes_256,
    "colors", "636f6c6f7273" => success
);

test_build_response!(
    build_xtgettcap_response_co_alias_same_branch,
    "Co", "436f" => success
);

test_build_response!(
    build_xtgettcap_response_unknown_starts_with_failure_prefix,
    "UNKNOWN", "554e4b4e4f574e" => failure
);

test_build_response!(
    build_xtgettcap_response_ms_encodes_clipboard_format,
    "Ms", "4d73" => success contains "4d73"
);

// ── Additional capability coverage (Smulx, Smol, Ss/Se, Su, ccc, U8/u8, Cr, bce, sitm/ritm, kt) ──

test_build_response!(build_xtgettcap_response_smulx_success, "Smulx", "536d756c78" => success);
test_build_response!(build_xtgettcap_response_smol_success,  "Smol",  "536d6f6c"   => success);
test_build_response!(build_xtgettcap_response_ss_success,    "Ss",    "5373"       => success);
test_build_response!(build_xtgettcap_response_se_success,    "Se",    "5365"       => success);
test_build_response!(build_xtgettcap_response_su_success,    "Su",    "5375"       => success);
test_build_response!(build_xtgettcap_response_ccc_success,   "ccc",   "636363"     => success);
test_build_response!(build_xtgettcap_response_u8_upper,      "U8",    "5538"       => success);
test_build_response!(build_xtgettcap_response_u8_lower,      "u8",    "7538"       => success);
test_build_response!(build_xtgettcap_response_cr_success,    "Cr",    "4372"       => success);
test_build_response!(build_xtgettcap_response_bce_success,   "bce",   "626365"     => success);
test_build_response!(build_xtgettcap_response_sitm_success,  "sitm",  "7369746d"   => success);
test_build_response!(build_xtgettcap_response_ritm_success,  "ritm",  "7269746d"   => success);
test_build_response!(build_xtgettcap_response_kt_success,    "kt",    "6b74"       => success);

#[path = "xtgettcap_payload.rs"]
mod payload;

use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(256))]

    #[test]
    // PANIC SAFETY: DCS XTGETTCAP with arbitrary hex-encoded capability name never panics
    fn prop_xtgettcap_arbitrary_hex_no_panic(
        cap in proptest::collection::vec(0u8..=255u8, 0..=30)
    ) {
        use std::fmt::Write as _;
        let mut term = crate::TerminalCore::new(24, 80);
        // Encode as hex string
        let mut hex = String::with_capacity(cap.len() * 2);
        for b in &cap { let _ = write!(hex, "{b:02X}"); }
        let seq = format!("\x1bP+q{hex}\x1b\\");
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }

    #[test]
    // PANIC SAFETY: DCS with arbitrary payload bytes never panics
    fn prop_dcs_arbitrary_payload_no_panic(
        payload in proptest::collection::vec(0x20u8..=0x7eu8, 0..=50)
    ) {
        let mut term = crate::TerminalCore::new(24, 80);
        let p = String::from_utf8(payload).unwrap_or_default();
        let seq = format!("\x1bP{p}\x1b\\");
        term.advance(seq.as_bytes());
        prop_assert!(term.screen.cursor().row < 24);
    }
}
