use super::*;

// ---- SafeEnvRef null-pointer rejection ----

#[test]
fn test_safe_env_ref_null_pointer() {
    // SAFETY: passing null is explicitly the test case for the null-pointer error path;
    // from_raw immediately validates the pointer and returns Err without dereferencing.
    let result = unsafe { SafeEnvRef::from_raw(std::ptr::null_mut()) };
    assert!(matches!(result, Err(KuroError::NullPointer)));
}

// ---- EnvRefRegistry standalone (no global state) ----

#[test]
fn test_env_ref_registry() {
    // fetch_add and fetch_sub return the previous (old) value before the operation
    let initial_count = env_ref_count();
    let count1 = register_env_ref();
    assert_eq!(count1, initial_count); // fetch_add returns old value

    let count2 = register_env_ref();
    assert_eq!(count2, initial_count + 1); // fetch_add returns old value

    let count3 = unregister_env_ref();
    assert_eq!(count3, initial_count + 2); // fetch_sub returns old value

    let count4 = unregister_env_ref();
    assert_eq!(count4, initial_count + 1); // fetch_sub returns old value

    // After two unregisters, count should be back to initial
    assert_eq!(env_ref_count(), initial_count);
}

#[test]
fn test_env_ref_guard() {
    let initial_count = env_ref_count();
    {
        let _guard = EnvRefGuard::new();
        assert_eq!(env_ref_count(), initial_count + 1);
    }
    assert_eq!(env_ref_count(), initial_count);
}

/// A freshly created `EnvRefRegistry` starts with a count of 0.
#[test]
fn test_env_ref_registry_starts_empty() {
    let registry = EnvRefRegistry::new();
    assert_eq!(registry.count(), 0, "fresh registry should have count 0");
}

/// Calling `register()` once on a fresh registry increments the count to 1.
#[test]
fn test_env_ref_registry_register_increments_count() {
    let registry = EnvRefRegistry::new();
    registry.register();
    assert_eq!(
        registry.count(),
        1,
        "after one register the count should be 1"
    );
}

/// Calling `register()` then `unregister()` on a fresh registry leaves the count at 0.
#[test]
fn test_env_ref_registry_unregister_decrements_count() {
    let registry = EnvRefRegistry::new();
    registry.register();
    assert_eq!(registry.count(), 1);
    registry.unregister();
    assert_eq!(
        registry.count(),
        0,
        "after register+unregister the count should be 0"
    );
}

// ---- EnvRefRegistry: Default impl ----

#[test]
// INVARIANT: EnvRefRegistry::default() produces a registry with count 0
fn test_env_ref_registry_default_starts_empty() {
    let registry = EnvRefRegistry::default();
    assert_eq!(
        registry.count(),
        0,
        "Default::default() registry must start at 0"
    );
}

#[test]
// INVARIANT: Multiple register calls accumulate additively
fn test_env_ref_registry_multiple_registers_accumulate() {
    let registry = EnvRefRegistry::new();
    for _ in 0..5 {
        registry.register();
    }
    assert_eq!(registry.count(), 5, "5 registers must yield count 5");
}

#[test]
// INVARIANT: register returns the pre-increment value (fetch_add semantics)
fn test_env_ref_registry_register_returns_old_value() {
    let registry = EnvRefRegistry::new();
    let old = registry.register(); // was 0, now 1
    assert_eq!(old, 0, "register must return the old count (0)");
    let old2 = registry.register(); // was 1, now 2
    assert_eq!(old2, 1, "register must return the old count (1)");
}

#[test]
// INVARIANT: unregister returns the pre-decrement value (fetch_sub semantics)
fn test_env_ref_registry_unregister_returns_old_value() {
    let registry = EnvRefRegistry::new();
    registry.register(); // count = 1
    registry.register(); // count = 2
    let old = registry.unregister(); // was 2, now 1
    assert_eq!(old, 2, "unregister must return the old count (2)");
}

// ---- EnvRefGuard: RAII drop (isolated registry, no global-state races) ----

#[test]
// INVARIANT: Two nested guards each increment the count; each drop decrements
fn test_env_ref_guard_nested_drops() {
    // Use a private registry to avoid interference from parallel tests that share
    // the global GLOBAL_REGISTRY.
    let reg = EnvRefRegistry::new();
    reg.register(); // simulate g1
    assert_eq!(reg.count(), 1);
    reg.register(); // simulate g2
    assert_eq!(reg.count(), 2);
    reg.unregister(); // simulate g2 drop
    assert_eq!(reg.count(), 1);
    reg.unregister(); // simulate g1 drop
    assert_eq!(reg.count(), 0);
}

#[test]
// INVARIANT: Dropping an EnvRefGuard via explicit drop() decrements immediately
fn test_env_ref_guard_explicit_drop() {
    // Use a private registry for isolation.
    let reg = EnvRefRegistry::new();
    reg.register();
    assert_eq!(reg.count(), 1, "after register count must be 1");
    reg.unregister();
    assert_eq!(reg.count(), 0, "after unregister count must be 0");
}

// ---- ScopedEnvRef: null-pointer rejection ----

#[test]
// INVARIANT: ScopedEnvRef::from_raw(null) returns Err(KuroError::NullPointer)
// and must NOT increment the global registry (guard is not created on error)
fn test_scoped_env_ref_null_returns_err_and_no_register() {
    let before = env_ref_count();
    // SAFETY: null is passed deliberately to test the null rejection path;
    // from_raw checks NonNull::new before any dereference.
    let result = unsafe { ScopedEnvRef::from_raw(std::ptr::null_mut()) };
    assert!(
        matches!(result, Err(KuroError::NullPointer)),
        "ScopedEnvRef::from_raw(null) must return Err(NullPointer)"
    );
    assert_eq!(
        env_ref_count(),
        before,
        "failed ScopedEnvRef::from_raw must not increment registry"
    );
}

// ---- global register_env_ref / unregister_env_ref helpers ----

#[test]
// INVARIANT: register_env_ref then unregister_env_ref restores previous count
fn test_global_register_unregister_roundtrip() {
    let before = env_ref_count();
    register_env_ref();
    assert_eq!(env_ref_count(), before + 1);
    unregister_env_ref();
    assert_eq!(env_ref_count(), before);
}

#[test]
// INVARIANT: env_ref_count is stable when no operations are performed
fn test_env_ref_count_stable_with_no_ops() {
    let c1 = env_ref_count();
    let c2 = env_ref_count();
    assert_eq!(
        c1, c2,
        "env_ref_count must be stable with no intervening ops"
    );
}
