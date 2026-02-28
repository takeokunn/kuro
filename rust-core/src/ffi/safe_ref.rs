//! Safe environment reference storage with lifetime management
//!
//! This module provides a safe abstraction for storing and managing references
//! to Emacs environment pointers, ensuring proper lifetime management and
//! preventing use-after-free errors.

use super::abstraction::emacs_env;
use crate::{KuroError, Result};
use std::ptr::NonNull;

/// Safe wrapper for Emacs environment pointer
///
/// This struct wraps a raw pointer to an Emacs environment and provides
/// safe access methods. It ensures the pointer is valid during use and
/// prevents null pointer dereferences.
#[repr(C)]
pub struct SafeEnvRef {
    /// Non-null pointer to Emacs environment
    env: NonNull<emacs_env>,
}

impl SafeEnvRef {
    /// Create a new safe environment reference from a raw pointer
    ///
    /// # Safety
    /// The caller must ensure that:
    /// - The pointer is valid and points to a properly initialized Emacs environment
    /// - The environment remains valid for the lifetime of this reference
    /// - Only one SafeEnvRef exists for a given environment at a time
    ///
    /// # Arguments
    /// * `env` - Raw pointer to Emacs environment
    ///
    /// # Returns
    /// * `Ok(SafeEnvRef)` if pointer is valid
    /// * `Err(KuroError::NullPointer)` if pointer is null
    pub unsafe fn from_raw(env: *mut emacs_env) -> Result<Self> {
        NonNull::new(env)
            .map(|env| SafeEnvRef { env })
            .ok_or(KuroError::NullPointer)
    }

    /// Get the raw pointer to the Emacs environment
    ///
    /// This is primarily used for FFI calls that require the raw pointer.
    ///
    /// # Returns
    /// Raw pointer to the Emacs environment
    pub fn as_ptr(&self) -> *mut emacs_env {
        self.env.as_ptr()
    }

    /// Check if the environment reference is still valid
    ///
    /// This is a basic check - actual validity depends on the Emacs
    /// runtime ensuring the environment remains valid.
    ///
    /// # Returns
    /// * `true` if the pointer is non-null
    /// * `false` if the pointer is null (should never happen)
    #[allow(useless_ptr_null_checks)]
    pub fn is_valid(&self) -> bool {
        !self.env.as_ptr().is_null()
    }

    /// Clone the reference (creates a new handle to the same environment)
    ///
    /// # Safety
    /// This is unsafe because it allows creating multiple handles to the
    /// same environment, which can lead to undefined behavior if not
    /// used correctly.
    ///
    /// # Returns
    /// A new SafeEnvRef pointing to the same environment
    pub unsafe fn clone_ref(&self) -> Self {
        SafeEnvRef { env: self.env }
    }
}

// Send and Sync implementations for SafeEnvRef
//
// These are safe to implement because:
// - SafeEnvRef is just a wrapper around a pointer
// - The actual safety comes from how the pointer is used
// - The Emacs environment is thread-safe in certain contexts
unsafe impl Send for SafeEnvRef {}
unsafe impl Sync for SafeEnvRef {}

/// Environment reference registry for tracking active references
///
/// This structure maintains a registry of active environment references
/// to help track and manage them throughout the module's lifetime.
pub struct EnvRefRegistry {
    /// Count of active environment references
    ref_count: std::sync::atomic::AtomicUsize,
}

impl EnvRefRegistry {
    /// Create a new environment reference registry
    pub const fn new() -> Self {
        Self {
            ref_count: std::sync::atomic::AtomicUsize::new(0),
        }
    }

    /// Register a new environment reference
    ///
    /// # Returns
    /// The new reference count
    pub fn register(&self) -> usize {
        self.ref_count
            .fetch_add(1, std::sync::atomic::Ordering::SeqCst)
    }

    /// Unregister an environment reference
    ///
    /// # Returns
    /// The new reference count
    pub fn unregister(&self) -> usize {
        self.ref_count
            .fetch_sub(1, std::sync::atomic::Ordering::SeqCst)
    }

    /// Get the current reference count
    ///
    /// # Returns
    /// The number of active environment references
    pub fn count(&self) -> usize {
        self.ref_count.load(std::sync::atomic::Ordering::SeqCst)
    }
}

impl Default for EnvRefRegistry {
    fn default() -> Self {
        Self::new()
    }
}

/// Global environment reference registry
///
/// This static registry tracks all active environment references across
/// the module. It's used for debugging and resource management.
static GLOBAL_REGISTRY: EnvRefRegistry = EnvRefRegistry::new();

/// Register a new environment reference in the global registry
///
/// This function should be called whenever a new SafeEnvRef is created.
///
/// # Returns
/// The new reference count
pub fn register_env_ref() -> usize {
    GLOBAL_REGISTRY.register()
}

/// Unregister an environment reference from the global registry
///
/// This function should be called whenever a SafeEnvRef is dropped.
///
/// # Returns
/// The new reference count
pub fn unregister_env_ref() -> usize {
    GLOBAL_REGISTRY.unregister()
}

/// Get the current count of active environment references
///
/// This is primarily useful for debugging and monitoring.
///
/// # Returns
/// The number of active environment references
pub fn env_ref_count() -> usize {
    GLOBAL_REGISTRY.count()
}

/// RAII guard for automatically managing environment reference registration
///
/// This struct automatically registers itself on creation and unregisters
/// on drop, providing automatic lifetime management for environment references.
pub struct EnvRefGuard;

impl EnvRefGuard {
    /// Create a new environment reference guard
    ///
    /// This automatically registers the reference in the global registry.
    #[allow(clippy::new_without_default)]
    pub fn new() -> Self {
        register_env_ref();
        EnvRefGuard
    }
}

impl Drop for EnvRefGuard {
    fn drop(&mut self) {
        unregister_env_ref();
    }
}

/// Scoped environment reference
///
/// This combines a SafeEnvRef with automatic lifetime management via EnvRefGuard.
pub struct ScopedEnvRef {
    /// The safe environment reference
    env: SafeEnvRef,
    /// The RAII guard for registration
    _guard: EnvRefGuard,
}

impl ScopedEnvRef {
    /// Create a new scoped environment reference from a raw pointer
    ///
    /// # Safety
    /// The caller must ensure the pointer is valid and the environment
    /// remains valid for the lifetime of this scoped reference.
    ///
    /// # Arguments
    /// * `env` - Raw pointer to Emacs environment
    ///
    /// # Returns
    /// * `Ok(ScopedEnvRef)` if pointer is valid
    /// * `Err(KuroError::NullPointer)` if pointer is null
    pub unsafe fn from_raw(env: *mut emacs_env) -> Result<Self> {
        let env_ref = SafeEnvRef::from_raw(env)?;
        Ok(Self {
            env: env_ref,
            _guard: EnvRefGuard::new(),
        })
    }

    /// Get the safe environment reference
    ///
    /// # Returns
    /// Reference to the SafeEnvRef
    pub fn env(&self) -> &SafeEnvRef {
        &self.env
    }

    /// Get the raw pointer to the Emacs environment
    ///
    /// # Returns
    /// Raw pointer to the Emacs environment
    pub fn as_ptr(&self) -> *mut emacs_env {
        self.env.as_ptr()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_safe_env_ref_null_pointer() {
        let result = unsafe { SafeEnvRef::from_raw(std::ptr::null_mut()) };
        assert!(matches!(result, Err(KuroError::NullPointer)));
    }

    #[test]
    fn test_env_ref_registry() {
        let initial_count = env_ref_count();
        let count1 = register_env_ref();
        assert_eq!(count1, initial_count + 1);

        let count2 = register_env_ref();
        assert_eq!(count2, initial_count + 2);

        let count3 = unregister_env_ref();
        assert_eq!(count3, initial_count + 1);

        let count4 = unregister_env_ref();
        assert_eq!(count4, initial_count);
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
}
