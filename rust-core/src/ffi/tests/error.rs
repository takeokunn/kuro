use super::*;

// ---- InitError::Display ----

#[test]
fn test_init_error_display() {
    let err = InitError::VersionMismatch {
        required: (29, 1),
        found: (28, 2),
    };
    assert!(err.to_string().contains("28.2"));
    assert!(err.to_string().contains("29.1"));

    let err = InitError::MissingFunction {
        function: "emacs-module-init".to_owned(),
    };
    assert!(err.to_string().contains("emacs-module-init"));

    let err = InitError::AlreadyInitialized;
    assert!(err.to_string().contains("already initialized"));

    let err = InitError::NotInitialized;
    assert!(err.to_string().contains("not been initialized"));
}

#[test]
// INVARIANT: VersionMismatch Display contains the word "incompatible"
fn test_init_error_version_mismatch_display_exact_keyword() {
    let err = InitError::VersionMismatch {
        required: (30, 0),
        found: (27, 5),
    };
    let s = err.to_string();
    assert!(
        s.contains("incompatible"),
        "VersionMismatch Display must contain 'incompatible', got: {s}"
    );
}

#[test]
// INVARIANT: MissingFunction Display contains the word "not available"
fn test_init_error_missing_function_display_exact_keyword() {
    let err = InitError::MissingFunction {
        function: "intern".to_owned(),
    };
    let s = err.to_string();
    assert!(
        s.contains("not available"),
        "MissingFunction Display must contain 'not available', got: {s}"
    );
}

#[test]
// INVARIANT: NotInitialized Display mentions "kuro-core-init"
fn test_init_error_not_initialized_display_mentions_init_fn() {
    let s = InitError::NotInitialized.to_string();
    assert!(
        s.contains("kuro-core-init"),
        "NotInitialized Display must mention 'kuro-core-init', got: {s}"
    );
}

// ---- InitError::Debug / Clone / PartialEq ----

#[test]
// INVARIANT: InitError implements Clone; clone is equal to the original
fn test_init_error_clone_eq() {
    let orig = InitError::MissingFunction {
        function: "funcall".to_owned(),
    };
    let cloned = orig.clone();
    assert_eq!(orig, cloned, "cloned InitError must equal original");
}

#[test]
// INVARIANT: Distinct InitError variants are not equal
fn test_init_error_ne_distinct_variants() {
    assert_ne!(InitError::AlreadyInitialized, InitError::NotInitialized);
}

#[test]
// INVARIANT: InitError implements Debug; output is non-empty
fn test_init_error_debug_non_empty() {
    let s = format!("{:?}", InitError::AlreadyInitialized);
    assert!(!s.is_empty(), "Debug output must not be empty");
}

// ---- StateError::Display ----

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
// INVARIANT: NoTerminalSession Display mentions "kuro-core-init"
fn test_state_error_no_session_mentions_init() {
    let s = StateError::NoTerminalSession.to_string();
    assert!(
        s.contains("kuro-core-init"),
        "NoTerminalSession must mention 'kuro-core-init', got: {s}"
    );
}

#[test]
// INVARIANT: TerminalSessionExists Display mentions "kuro-core-shutdown"
fn test_state_error_session_exists_mentions_shutdown() {
    let s = StateError::TerminalSessionExists.to_string();
    assert!(
        s.contains("kuro-core-shutdown"),
        "TerminalSessionExists must mention 'kuro-core-shutdown', got: {s}"
    );
}

#[test]
// INVARIANT: StateError implements Clone; clone equals original
fn test_state_error_clone_eq() {
    let orig = StateError::TerminalSessionExists;
    assert_eq!(orig.clone(), orig);
}

// ---- RuntimeError::Display ----

#[test]
fn test_runtime_error_display() {
    let err = RuntimeError::PtySpawnFailed {
        command: "bash".to_owned(),
        message: "Permission denied".to_owned(),
    };
    assert!(err.to_string().contains("bash"));
    assert!(err.to_string().contains("Permission denied"));

    let err = RuntimeError::PtyOperationFailed {
        operation: "write".to_owned(),
        message: "Broken pipe".to_owned(),
    };
    assert!(err.to_string().contains("write"));
    assert!(err.to_string().contains("Broken pipe"));

    let err = RuntimeError::ParseError {
        message: "Invalid CSI sequence".to_owned(),
    };
    assert!(err.to_string().contains("Invalid CSI sequence"));

    let err = RuntimeError::InvalidParameter {
        param: "rows".to_owned(),
        message: "must be positive".to_owned(),
    };
    assert!(err.to_string().contains("rows"));
    assert!(err.to_string().contains("must be positive"));
}

#[test]
// INVARIANT: AllocationFailed Display contains "Memory allocation failed"
fn test_runtime_error_allocation_failed_display() {
    let err = RuntimeError::AllocationFailed {
        message: "out of memory".to_owned(),
    };
    let s = err.to_string();
    assert!(
        s.contains("Memory allocation failed"),
        "AllocationFailed must mention 'Memory allocation failed', got: {s}"
    );
    assert!(
        s.contains("out of memory"),
        "AllocationFailed must include the message payload, got: {s}"
    );
}

#[test]
// INVARIANT: FfiError Display starts with "FFI error:"
fn test_runtime_error_ffi_error_display() {
    let err = RuntimeError::FfiError {
        message: "bad handle".to_owned(),
    };
    let s = err.to_string();
    assert!(
        s.contains("FFI error"),
        "FfiError Display must contain 'FFI error', got: {s}"
    );
    assert!(
        s.contains("bad handle"),
        "FfiError Display must include the message payload, got: {s}"
    );
}

#[test]
// INVARIANT: PtySpawnFailed Display contains "Failed to spawn PTY"
fn test_runtime_error_pty_spawn_contains_prefix() {
    let err = RuntimeError::PtySpawnFailed {
        command: "fish".to_owned(),
        message: "ENOENT".to_owned(),
    };
    let s = err.to_string();
    assert!(
        s.contains("Failed to spawn PTY"),
        "PtySpawnFailed Display must contain 'Failed to spawn PTY', got: {s}"
    );
}

#[test]
// INVARIANT: RuntimeError implements Clone and PartialEq
fn test_runtime_error_clone_eq() {
    let orig = RuntimeError::ParseError {
        message: "bad byte".to_owned(),
    };
    assert_eq!(orig.clone(), orig);
}

// ---- From conversions ----

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
        command: "bash".to_owned(),
        message: "error".to_owned(),
    }
    .into();
    assert!(matches!(kuro_err, KuroError::Runtime(_)));
}

#[test]
// INVARIANT: From<StateError::AlreadyInitialized> wraps into KuroError::State
fn test_state_error_already_initialized_into_kuro_error() {
    let e: KuroError = StateError::AlreadyInitialized.into();
    assert!(matches!(
        e,
        KuroError::State(StateError::AlreadyInitialized)
    ));
}

#[test]
// INVARIANT: From<RuntimeError::FfiError> wraps into KuroError::Runtime
fn test_runtime_ffi_error_into_kuro_error() {
    let e: KuroError = RuntimeError::FfiError {
        message: "test".to_owned(),
    }
    .into();
    assert!(matches!(
        e,
        KuroError::Runtime(RuntimeError::FfiError { .. })
    ));
}

// ---- Helper functions ----

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

#[test]
// INVARIANT: ffi_error helper produces KuroError::Runtime(RuntimeError::FfiError)
fn test_ffi_error_helper_produces_correct_variant() {
    let e = ffi_error("bad call");
    assert!(
        matches!(e, KuroError::Runtime(RuntimeError::FfiError { .. })),
        "ffi_error must produce KuroError::Runtime(FfiError)"
    );
}

#[test]
// INVARIANT: pty_spawn_error preserves the command and message payload
fn test_pty_spawn_error_helper_display_contains_payload() {
    let e = pty_spawn_error("nvim", "permission denied");
    let s = format!("{e}");
    assert!(
        s.contains("nvim"),
        "pty_spawn_error display must contain command"
    );
    assert!(
        s.contains("permission denied"),
        "pty_spawn_error display must contain message"
    );
}

#[test]
// INVARIANT: parse_error helper preserves the message payload in Display
fn test_parse_error_helper_display_contains_payload() {
    let e = parse_error("unexpected byte 0x9b");
    let s = format!("{e}");
    assert!(
        s.contains("unexpected byte 0x9b"),
        "parse_error display must contain message, got: {s}"
    );
}

#[test]
// INVARIANT: invalid_parameter_error helper preserves both param and message
fn test_invalid_parameter_error_helper_display_contains_both_fields() {
    let e = invalid_parameter_error("timeout_ms", "must be >= 0");
    let s = format!("{e}");
    assert!(s.contains("timeout_ms"), "must contain param name");
    assert!(s.contains("must be >= 0"), "must contain error message");
}
