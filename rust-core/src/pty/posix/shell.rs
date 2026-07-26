//! Executable validation for POSIX PTYs.

use crate::{
    ffi::error::{invalid_parameter_error, pty_spawn_error},
    Result,
};
use std::fs::File;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt as _;
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Eq, PartialEq)]
pub(super) struct ShellCommand {
    path: PathBuf,
}

impl ShellCommand {
    /// Validate an executable command.
    ///
    /// The command must already be an absolute path to an existing executable
    /// regular file. `$PATH` is intentionally ignored so validation and exec use
    /// the same filesystem object.
    pub(super) fn resolve(command: &str) -> Result<Self> {
        let requested_path = Path::new(command);
        if !requested_path.is_absolute() {
            return Err(invalid_parameter_error(
                "command",
                "Shell command must be an absolute path",
            ));
        }

        let path = requested_path.to_path_buf();
        open_executable(&path)?;
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
}

/// Open and validate the exact filesystem object that will be executed.
pub(super) fn open_executable(path: &Path) -> Result<File> {
    let file = File::open(path).map_err(|_| {
        invalid_parameter_error("command", "Shell path does not exist or is inaccessible")
    })?;
    let meta = file.metadata().map_err(|_| {
        invalid_parameter_error("command", "Shell path does not exist or is inaccessible")
    })?;

    if !meta.is_file() {
        return Err(invalid_parameter_error(
            "command",
            "Shell path is not a regular file",
        ));
    }

    if meta.permissions().mode() & 0o111 == 0 {
        return Err(invalid_parameter_error(
            "command",
            "Shell is not executable",
        ));
    }

    Ok(file)
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
