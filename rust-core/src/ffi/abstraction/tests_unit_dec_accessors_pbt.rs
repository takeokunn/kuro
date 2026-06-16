use super::tests_support::{build_osc133_d, take_single_prompt_mark, MAX_PROMPT_DURATION_MS};
use proptest::prelude::*;

// ---------------------------------------------------------------------------
// FR-124 PBT: random aid/duration/err_path triples round-trip through the
// parser into the drained Vec exactly.
// ---------------------------------------------------------------------------

// Restrict err_path to printable ASCII without OSC delimiters (`;`, `\x1b`,
// controls). The parser drops values containing C0/DEL bytes (see
// `parser/osc_protocol.rs::has_control_bytes`); the property here
// asserts round-trip on inputs the parser is contractually required
// to preserve.
fn safe_err_str(max_len: usize) -> impl Strategy<Value = String> {
    prop::collection::vec(
        prop_oneof![
            32u8..=58u8,  // ' ' .. ':'  (excludes ';' = 0x3B)
            60u8..=126u8, // '<' .. '~'  (excludes DEL)
        ],
        0..=max_len,
    )
    .prop_map(|v| String::from_utf8(v).expect("ASCII subset is always valid UTF-8"))
}

/// Strict printable-ASCII generator for `aid=` values (`[!-~]+`, no `;` or `=`).
/// Mirrors the `is_printable_aid` parser-side predicate (Security W1).
fn safe_aid_str(max_len: usize) -> impl Strategy<Value = String> {
    prop::collection::vec(
        prop_oneof![
            33u8..=58u8,  // '!' .. ':'  (excludes ';' = 0x3B and ' ' = 0x20)
            60u8..=60u8,  // '<'         (excludes '=' = 0x3D)
            62u8..=126u8, // '>' .. '~'  (excludes DEL)
        ],
        0..=max_len,
    )
    .prop_map(|v| String::from_utf8(v).expect("ASCII subset is always valid UTF-8"))
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(64))]

    #[test]
    fn prop_osc133_d_extras_roundtrip_through_parser(
        exit_code in -128i32..=127i32,
        aid_opt in proptest::option::of(safe_aid_str(64)),
        duration_opt in proptest::option::of(0u64..=MAX_PROMPT_DURATION_MS),
        err_opt in proptest::option::of(safe_err_str(64)),
    ) {
        let payload = build_osc133_d(
            exit_code,
            aid_opt.as_deref(),
            duration_opt,
            err_opt.as_deref(),
        );

        let ev = take_single_prompt_mark(&payload);
        prop_assert!(matches!(ev.mark, crate::types::osc::PromptMark::CommandEnd));
        prop_assert_eq!(ev.exit_code, Some(exit_code));
        prop_assert_eq!(ev.aid.clone(), aid_opt);
        prop_assert_eq!(ev.duration_ms, duration_opt);
        prop_assert_eq!(ev.err_path.clone(), err_opt);
    }
}
