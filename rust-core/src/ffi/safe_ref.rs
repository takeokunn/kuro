//! Callback-scoped environment reference storage with lifetime management
//!
//! Emacs `emacs_env` pointers are callback-scoped capabilities. They must not be
//! cloned into multiple live handles or moved/shared across threads.

use super::abstraction::emacs_env;
use crate::{KuroError, Result};
use std::{marker::PhantomData, ptr::NonNull, rc::Rc};

/// Callback-scoped wrapper for an Emacs environment pointer.
///
/// This type is intentionally `!Send` and `!Sync`; an Emacs environment is only
/// valid for the callback/thread that supplied it.
///
/// ```compile_fail
/// use kuro_core::ffi::{emacs_env, SafeEnvRef};
///
/// let env = std::ptr::NonNull::<emacs_env>::dangling().as_ptr();
/// let safe_env = unsafe { SafeEnvRef::from_raw(env).unwrap() };
///
/// std::thread::spawn(move || {
///     let _ = safe_env.as_ptr();
/// });
/// ```
pub struct SafeEnvRef<'env> {
    /// Non-null pointer to Emacs environment
    env: NonNull<emacs_env>,
    _scope: PhantomData<&'env mut emacs_env>,
    _not_send_sync: PhantomData<Rc<()>>,
}

impl<'env> SafeEnvRef<'env> {
    /// Create a new safe environment reference from a raw pointer
    ///
    /// # Safety
    /// The caller must ensure that:
    /// - The pointer is valid and points to a properly initialized Emacs environment
    /// - The environment remains valid for `'env`
    /// - `'env` does not outlive the Emacs callback that supplied the pointer
    /// - Only one live `SafeEnvRef` exists for a given environment at a time
    ///
    /// # Errors
    /// Returns `Err(KuroError::NullPointer)` if `env` is null.
    pub unsafe fn from_raw(env: *mut emacs_env) -> Result<Self> {
        NonNull::new(env)
            .map(|env| Self {
                env,
                _scope: PhantomData,
                _not_send_sync: PhantomData,
            })
            .ok_or(KuroError::NullPointer)
    }

    /// Get the raw pointer to the Emacs environment
    ///
    /// This is primarily used for FFI calls that require the raw pointer.
    ///
    /// # Returns
    /// Raw pointer to the Emacs environment
    #[must_use]
    pub const fn as_ptr(&self) -> *mut emacs_env {
        self.env.as_ptr()
    }
}

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
    #[must_use]
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
/// This function should be called whenever a new `SafeEnvRef` is created.
///
/// # Returns
/// The new reference count
pub fn register_env_ref() -> usize {
    GLOBAL_REGISTRY.register()
}

/// Unregister an environment reference from the global registry
///
/// This function should be called whenever a `SafeEnvRef` is dropped.
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
    #[expect(
        clippy::new_without_default,
        reason = "EnvRefGuard::new() has a side effect (register_env_ref); a Default impl would be misleading"
    )]
    #[must_use]
    pub fn new() -> Self {
        register_env_ref();
        Self
    }
}

impl Drop for EnvRefGuard {
    fn drop(&mut self) {
        unregister_env_ref();
    }
}

/// Scoped environment reference
///
/// This combines a `SafeEnvRef` with automatic lifetime management via `EnvRefGuard`.
pub struct ScopedEnvRef<'env> {
    /// The safe environment reference
    env: SafeEnvRef<'env>,
    /// The RAII guard for registration
    _guard: EnvRefGuard,
}

impl<'env> ScopedEnvRef<'env> {
    /// Create a new scoped environment reference from a raw pointer
    ///
    /// # Safety
    /// The caller must ensure the pointer is valid and the environment
    /// remains valid for `'env`.
    ///
    /// # Errors
    /// Returns `Err(KuroError::NullPointer)` if `env` is null.
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
    /// Reference to the `SafeEnvRef`
    #[must_use]
    pub const fn env(&self) -> &SafeEnvRef<'env> {
        &self.env
    }

    /// Get the raw pointer to the Emacs environment
    ///
    /// # Returns
    /// Raw pointer to the Emacs environment
    #[must_use]
    pub const fn as_ptr(&self) -> *mut emacs_env {
        self.env.as_ptr()
    }
}

#[cfg(test)]
#[path = "tests/safe_ref.rs"]
mod tests;
