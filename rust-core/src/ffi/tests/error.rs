use super::*;

#[test]
fn test_init_error_display() {
    let err = InitError::VersionMismatch {
        required: (29, 1),
        found: (28, 2),
    };
    assert!(err.to_string().contains("28.2"));
    assert!(err.to_string().contains("29.1"));

    let err = InitError::MissingFunction {
        function: "emacs-module-init".to_string(),
    };
    assert!(err.to_string().contains("emacs-module-init"));

    let err = InitError::AlreadyInitialized;
    assert!(err.to_string().contains("already initialized"));

    let err = InitError::NotInitialized;
    assert!(err.to_string().contains("not been initialized"));
}

#[test]
fn test_state_error_display() {
    let err = StateError::NotInitialized;
    assert!(err.to_string().contains("not initialized"));

    let err = StateError::AlreadyInitialized;
    assert!(err.to_string().contains("already initialized"));

    let err = StateError::NoTerminalSession;
    assert!(err.to_string().contains("No terminal session"));

    let err = StateError::TerminalSessionExists;
    assert!(err.to_string().contains("already exists"));
}

#[test]
fn test_runtime_error_display() {
    let err = RuntimeError::PtySpawnFailed {
        command: "bash".to_string(),
        message: "Permission denied".to_string(),
    };
    assert!(err.to_string().contains("bash"));
    assert!(err.to_string().contains("Permission denied"));

    let err = RuntimeError::PtyOperationFailed {
        operation: "write".to_string(),
        message: "Broken pipe".to_string(),
    };
    assert!(err.to_string().contains("write"));
    assert!(err.to_string().contains("Broken pipe"));

    let err = RuntimeError::ParseError {
        message: "Invalid CSI sequence".to_string(),
    };
    assert!(err.to_string().contains("Invalid CSI sequence"));

    let err = RuntimeError::InvalidParameter {
        param: "rows".to_string(),
        message: "must be positive".to_string(),
    };
    assert!(err.to_string().contains("rows"));
    assert!(err.to_string().contains("must be positive"));
}

#[test]
fn test_error_conversions() {
    let kuro_err: KuroError = InitError::VersionMismatch {
        required: (29, 1),
        found: (28, 1),
    }
    .into();
    assert!(matches!(kuro_err, KuroError::Init(_)));

    let kuro_err: KuroError = StateError::NotInitialized.into();
    assert!(matches!(kuro_err, KuroError::State(_)));

    let kuro_err: KuroError = RuntimeError::PtySpawnFailed {
        command: "bash".to_string(),
        message: "error".to_string(),
    }
    .into();
    assert!(matches!(kuro_err, KuroError::Runtime(_)));
}

#[test]
fn test_helper_functions() {
    let err = pty_spawn_error("zsh", "No such file");
    assert!(matches!(err, KuroError::Runtime(_)));

    let err = pty_operation_error("read", "EOF");
    assert!(matches!(err, KuroError::Runtime(_)));

    let err = parse_error("Invalid escape sequence");
    assert!(matches!(err, KuroError::Runtime(_)));

    let err = invalid_parameter_error("cols", "must be > 0");
    assert!(matches!(err, KuroError::Runtime(_)));
}
