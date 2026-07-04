//! Wiring for `vte_handler` parsing tests.

#[macro_use]
#[path = "vte_handler/tests_support.rs"]
mod tests_support;

pub(crate) use tests_support::{
    assert_no_pending_responses, assert_pending_response_count, first_pending_response_bytes,
};

#[path = "vte_handler/tests_cases.rs"]
mod tests_cases;
