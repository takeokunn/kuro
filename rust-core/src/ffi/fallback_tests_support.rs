use crate::ffi::emacs_env;

pub(crate) fn null_env() -> *mut emacs_env {
    std::ptr::null_mut()
}
