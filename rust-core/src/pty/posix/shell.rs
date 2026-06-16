//! Shell resolution and whitelist validation for POSIX PTYs.

use crate::{
    ffi::error::{invalid_parameter_error, pty_spawn_error},
    Result,
};
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt as _;
use std::path::{Path, PathBuf};

/// Allowed shells whitelist for security.
const ALLOWED_SHELLS: &[&str] = &["bash", "zsh", "sh", "fish"];

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct ShellCommand {
    path: PathBuf,
}

impl ShellCommand {
    /// Search `$PATH` for an executable named `command`.
    ///
    /// Returns the first absolute path found, or `None` if not found.
    pub(super) fn find_in_path(command: &str) -> Option<PathBuf> {
        if command.is_empty() {
            return None;
        }
        let path_var = std::env::var("PATH").unwrap_or_default();
        for dir in path_var.split(':') {
            if dir.is_empty() {
                continue;
            }
            let candidate = PathBuf::from(dir).join(command);
            if candidate.is_file() {
                return Some(candidate);
            }
        }
        None
    }

    /// Validate shell command against whitelist.
    ///
    /// Ensures only allowed shells can be spawned to prevent command injection.
    /// Resolves the command to an absolute path and checks the basename.
    pub(super) fn resolve(command: &str) -> Result<Self> {
        let path = if Path::new(command).is_absolute() {
            Self::validate_absolute_path(command)?
        } else {
            Self::find_in_path(command).ok_or_else(|| {
                invalid_parameter_error("command", &format!("Shell not found in PATH: {command}"))
            })?
        };

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

    fn validate_absolute_path(command: &str) -> Result<PathBuf> {
        // Absolute path: validate directly without PATH lookup.
        // This handles NixOS Nix store paths where the Rust process inherits
        // Emacs's restricted PATH and PATH lookup cannot locate the binary.
        let path = PathBuf::from(command);
        let meta = std::fs::metadata(&path).map_err(|_| {
            invalid_parameter_error("command", "Shell path does not exist or is inaccessible")
        })?;

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
