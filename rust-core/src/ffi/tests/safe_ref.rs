use super::*;

#[test]
fn test_safe_env_ref_null_pointer() {
    // SAFETY: passing null is explicitly the test case for the null-pointer error path;
    // from_raw immediately validates the pointer and returns Err without dereferencing.
    let result = unsafe { SafeEnvRef::from_raw(std::ptr::null_mut()) };
    assert!(matches!(result, Err(KuroError::NullPointer)));
}

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
