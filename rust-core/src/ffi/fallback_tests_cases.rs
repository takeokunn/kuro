use super::tests_support::null_env;
use crate::ffi::emacs_env;
use crate::ffi::fallback::emacs_funcall_exit;
use crate::RawFFI;

#[test]
fn test_raw_ffi_trait_impl() {
    // Verify RawFFI implements KuroFFI
    // Note: KuroFFI is not dyn compatible
    let _ = &RawFFI;
}

#[test]
fn test_placeholder_functions() {
    // Test placeholder functions don't crash
    let env = null_env();
    let nil = RawFFI::make_nil(env);
    assert!(nil.is_null());

    let t_val = RawFFI::make_bool(env, true);
    assert!(!t_val.is_null());

    let f_val = RawFFI::make_bool(env, false);
    assert!(f_val.is_null());

    let int_val = RawFFI::make_integer(env, 42);
    assert!(!int_val.is_null());

    let negative_int_val = RawFFI::make_integer(env, -1);
    assert!(!negative_int_val.is_null());

    let max_int_val = RawFFI::make_integer(env, i64::MAX);
    assert!(!max_int_val.is_null());

    let str_val = RawFFI::make_string(env, "hello");
    assert!(!str_val.is_null());

    let pair = RawFFI::cons(env, int_val, str_val);
    assert!(!pair.is_null());
}

// --- Tests migrated from src/tests/unit/ffi/kuro_ffi_module.rs ---

// --- emacs_funcall_exit - discriminant values (C ABI contract) ---

#[test]
fn test_pbt_funcall_exit_return_discriminant() {
    let val = emacs_funcall_exit::EmacsFuncallExitReturn as i32;
    assert_eq!(val, 0, "EmacsFuncallExitReturn must have discriminant 0");
}

#[test]
fn test_pbt_funcall_exit_signal_discriminant() {
    let val = emacs_funcall_exit::EmacsFuncallExitSignal as i32;
    assert_eq!(val, 1, "EmacsFuncallExitSignal must have discriminant 1");
}

#[test]
fn test_pbt_funcall_exit_throw_discriminant() {
    let val = emacs_funcall_exit::EmacsFuncallExitThrow as i32;
    assert_eq!(val, 2, "EmacsFuncallExitThrow must have discriminant 2");
}

#[test]
fn test_pbt_funcall_exit_discriminants_distinct() {
    let r = emacs_funcall_exit::EmacsFuncallExitReturn as i32;
    let s = emacs_funcall_exit::EmacsFuncallExitSignal as i32;
    let t = emacs_funcall_exit::EmacsFuncallExitThrow as i32;
    assert_ne!(r, s, "Return and Signal discriminants must differ");
    assert_ne!(r, t, "Return and Throw discriminants must differ");
    assert_ne!(s, t, "Signal and Throw discriminants must differ");
}

// --- RawFFI - compile-time and public-surface tests ---

#[test]
fn test_pbt_raw_ffi_is_zero_sized() {
    assert_eq!(
        std::mem::size_of::<RawFFI>(),
        0,
        "RawFFI must be a zero-sized unit struct"
    );
}

#[test]
fn test_pbt_raw_ffi_constructible() {
    let _ffi = RawFFI;
}

// --- KuroFFI trait - compile-time coverage ---

#[test]
fn test_pbt_raw_ffi_implements_kuro_ffi_trait() {
    use crate::ffi::kuro_ffi::KuroFFI as _;
    let env: *mut emacs_env = std::ptr::null_mut();
    let result = RawFFI::shutdown(env);
    let _ = result;
}
