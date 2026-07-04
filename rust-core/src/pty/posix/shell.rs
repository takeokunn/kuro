//! Shell allowlist validation for POSIX PTYs.

use crate::{
    ffi::error::{invalid_parameter_error, pty_spawn_error},
    Result,
};
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt as _;
use std::path::{Path, PathBuf};

/// Allowed shell basenames for security.
const ALLOWED_SHELLS: &[&str] = &["bash", "zsh", "sh", "fish"];

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct ShellCommand {
    path: PathBuf,
}

impl ShellCommand {
    /// Validate shell command against the allowlist.
    ///
    /// Ensures only allowed shells can be spawned to prevent command injection.
    /// The command must already be an absolute path; `$PATH` is intentionally
    /// ignored so validation and exec use the same filesystem object.
    pub(super) fn resolve(command: &str) -> Result<Self> {
        let requested_path = Path::new(command);
        if !requested_path.is_absolute() {
            return Err(invalid_parameter_error(
                "command",
                "Shell command must be an absolute path",
            ));
        }

        let path = Self::validate_absolute_path(requested_path)?;

        let basename = path
            .file_name()
            .and_then(|n| n.to_str())
            .ok_or_else(|| invalid_parameter_error("command", "Invalid shell name"))?;

        if !ALLOWED_SHELLS.contains(&basename) {
            return Err(invalid_parameter_error(
                "command",
                &format!(
                    "Shell '{}' not allowed. Allowed shells: {}",
                    basename,
                    ALLOWED_SHELLS.join(", ")
                ),
            ));
        }

        Ok(Self { path })
    }

    #[inline]
    pub(super) fn as_path(&self) -> &Path {
        &self.path
    }

    #[inline]
    #[cfg(test)]
    pub(super) fn into_path(self) -> PathBuf {
        self.path
    }

    fn validate_absolute_path(path: &Path) -> Result<PathBuf> {
        // Absolute path: validate directly without PATH lookup. This handles
        // NixOS store paths and keeps validation aligned with the exec target.
        let path = path.to_path_buf();
        let meta = std::fs::metadata(&path).map_err(|_| {
            invalid_parameter_error("command", "Shell path does not exist or is inaccessible")
        })?;

        if !meta.is_file() {
            return Err(invalid_parameter_error(
                "command",
                "Shell path is not a regular file",
            ));
        }

        // Symlinks are followed by metadata(); the kernel still performs final
        // permission enforcement at execv(2) time.
        if meta.permissions().mode() & 0o111 == 0 {
            return Err(invalid_parameter_error(
                "command",
                "Shell is not executable",
            ));
        }

        Ok(path)
    }
}

pub(super) fn shell_path_to_cstring(path: &Path, command: &str) -> Result<std::ffi::CString> {
    std::ffi::CString::new(
        path.to_str()
            .ok_or_else(|| pty_spawn_error(command, "Shell path is not valid UTF-8"))?,
    )
    .map_err(|e| pty_spawn_error(command, &format!("Invalid shell path: {e}")))
}

pub(super) fn shell_name_to_cstring(path: &Path, command: &str) -> Result<std::ffi::CString> {
    let shell_name = path.file_name().and_then(|n| n.to_str()).unwrap_or("sh");
    std::ffi::CString::new(shell_name)
        .map_err(|e| pty_spawn_error(command, &format!("Invalid shell name: {e}")))
}
