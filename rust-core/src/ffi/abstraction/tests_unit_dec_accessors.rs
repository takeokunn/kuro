#[path = "tests_unit_dec_accessors_support.rs"]
mod tests_support;

pub(crate) use crate::ffi::abstraction::tests_unit::make_session;

#[path = "tests_unit_dec_accessors_basic.rs"]
mod basic;

#[path = "tests_unit_dec_accessors_prompt.rs"]
mod prompt;

#[path = "tests_unit_dec_accessors_pbt.rs"]
mod pbt;
