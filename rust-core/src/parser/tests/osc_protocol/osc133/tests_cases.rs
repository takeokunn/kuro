// ── parser::tests::osc_protocol::osc133 ──────────────────────────────────────
//
// All OSC 133 shell-integration tests live in child modules:
//   - marks.rs: prompt-mark dispatch and exit-code parsing
//   - extras.rs: aid/duration/err handling and FR-119 edge cases
//   - limits.rs: payload-length caps and invalid UTF-8 skipping
//
// Shared macros (`test_osc_133_mark!`, `test_osc_133_exit_code!`) live in
// `support.rs`.

pub(super) use super::handle_osc_133;

#[path = "extras.rs"]
mod extras;
#[path = "limits.rs"]
mod limits;
#[path = "marks.rs"]
mod marks;
