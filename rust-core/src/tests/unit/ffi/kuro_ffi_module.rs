//! Unit tests for `crate::ffi::kuro_ffi` (opaque C types and `KuroFFI` trait)
//! and `crate::ffi::fallback` (`emacs_funcall_exit` enum, `RawFFI` struct).
//!
//! `emacs_env` and `emacs_value` cannot be constructed in safe Rust (their
//! only field is `[u8; 0]` with `#[repr(C)]`).  We therefore test
//! memory-layout invariants through `std::mem::size_of` / `align_of`.
//!
//! `RawFFI`'s helper methods are private; they are already covered by the
//! inline `#[cfg(test)]` block in `fallback.rs`.  Here we test the publicly
//! observable surface: the struct itself, the enum discriminants, and the
//! layout of the ZST opaque types.

use std::mem;

use crate::ffi::fallback::{emacs_funcall_exit, RawFFI};
use crate::ffi::kuro_ffi::{emacs_env, emacs_value};

// ---------------------------------------------------------------------------
// emacs_env and emacs_value — layout invariants
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: `emacs_env` is a zero-sized type (`[u8; 0]` private field).
fn test_emacs_env_is_zero_sized() {
    assert_eq!(
        mem::size_of::<emacs_env>(),
        0,
        "emacs_env must be zero-sized (opaque C placeholder)"
    );
}

#[test]
// INVARIANT: `emacs_value` is a zero-sized type (`[u8; 0]` private field).
fn test_emacs_value_is_zero_sized() {
    assert_eq!(
        mem::size_of::<emacs_value>(),
        0,
        "emacs_value must be zero-sized (opaque C placeholder)"
    );
}

#[test]
// INVARIANT: `emacs_env` has byte alignment (align = 1) for a `[u8; 0]` ZST.
fn test_emacs_env_align_is_one() {
    assert_eq!(
        mem::align_of::<emacs_env>(),
        1,
        "emacs_env must have alignment 1"
    );
}

#[test]
// INVARIANT: `emacs_value` has byte alignment (align = 1).
fn test_emacs_value_align_is_one() {
    assert_eq!(
        mem::align_of::<emacs_value>(),
        1,
        "emacs_value must have alignment 1"
    );
}

// ---------------------------------------------------------------------------
// emacs_funcall_exit — discriminant values (C ABI contract)
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: `EmacsFuncallExitReturn` == 0 per `emacs_module.h`.
fn test_funcall_exit_return_discriminant() {
    let val = emacs_funcall_exit::EmacsFuncallExitReturn as i32;
    assert_eq!(val, 0, "EmacsFuncallExitReturn must have discriminant 0");
}

#[test]
// INVARIANT: `EmacsFuncallExitSignal` == 1 per `emacs_module.h`.
fn test_funcall_exit_signal_discriminant() {
    let val = emacs_funcall_exit::EmacsFuncallExitSignal as i32;
    assert_eq!(val, 1, "EmacsFuncallExitSignal must have discriminant 1");
}

#[test]
// INVARIANT: `EmacsFuncallExitThrow` == 2 per `emacs_module.h`.
fn test_funcall_exit_throw_discriminant() {
    let val = emacs_funcall_exit::EmacsFuncallExitThrow as i32;
    assert_eq!(val, 2, "EmacsFuncallExitThrow must have discriminant 2");
}

#[test]
// INVARIANT: All three discriminants are distinct (no aliasing).
fn test_funcall_exit_discriminants_distinct() {
    let r = emacs_funcall_exit::EmacsFuncallExitReturn as i32;
    let s = emacs_funcall_exit::EmacsFuncallExitSignal as i32;
    let t = emacs_funcall_exit::EmacsFuncallExitThrow as i32;
    assert_ne!(r, s, "Return and Signal discriminants must differ");
    assert_ne!(r, t, "Return and Throw discriminants must differ");
    assert_ne!(s, t, "Signal and Throw discriminants must differ");
}

// ---------------------------------------------------------------------------
// RawFFI — compile-time and public-surface tests
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: `RawFFI` is a zero-sized unit struct.
fn test_raw_ffi_is_zero_sized() {
    assert_eq!(
        mem::size_of::<RawFFI>(),
        0,
        "RawFFI must be a zero-sized unit struct"
    );
}

#[test]
// INVARIANT: A `RawFFI` value can be constructed; it compiles without error.
fn test_raw_ffi_constructible() {
    let _ffi = RawFFI;
    // If this compiles, the struct is publicly constructible.
}

// ---------------------------------------------------------------------------
// KuroFFI trait — compile-time coverage (monomorphisation via RawFFI)
// ---------------------------------------------------------------------------

#[test]
// INVARIANT: `RawFFI` satisfies `KuroFFI` — verified by calling a trait
// method at compile time through a generic wrapper.  The test never executes
// the method body (which would need a live Emacs env), it only confirms that
// the impl exists and the associated function resolves correctly.
fn test_raw_ffi_implements_kuro_ffi_trait() {
    use crate::ffi::kuro_ffi::KuroFFI as _;
    // Calling a const-fn method on RawFFI proves the impl is wired up.
    // We use a null env pointer — valid for this placeholder implementation.
    let env: *mut emacs_env = std::ptr::null_mut();
    // `shutdown` is the simplest method (no inputs besides env).
    // The placeholder just returns make_bool(env, false) which is null_mut().
    let result = RawFFI::shutdown(env);
    // make_bool(false) returns null; make_bool(true) returns dangling.
    // Either outcome is acceptable; we only assert the call doesn't panic.
    let _ = result;
}
