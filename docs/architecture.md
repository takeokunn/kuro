# Kuro Architecture

## Overview

Kuro implements the **Remote Display Model**:
- **Rust Core**: All terminal logic and state
- **Emacs Lisp**: Display and view layer only
- **FFI Bridge**: Direct function calls for performance

## Components

### Rust Core

```
rust-core/src/
├── types/      # Data types
│   ├── color.rs    # Color (Named, Indexed, RGB)
│   └── cell.rs     # Cell with SGR attributes
├── grid/       # Virtual screen
│   ├── line.rs     # Line of cells with dirty tracking
│   └── screen.rs   # Screen with cursor and scroll region
├── parser/     # VTE parsing
│   ├── vte_handler.rs  # vte::Perform trait
│   └── sgr.rs          # SGR parameter parsing
├── pty/        # PTY management
│   ├── posix.rs        # POSIX PTY operations
│   └── reader.rs       # Threaded PTY reading
└── ffi/        # Emacs FFI
    └── bridge.rs       # emacs-module-rs bindings
```

### Emacs Lisp UI

```
emacs-lisp/
├── kuro.el         # User-facing API
├── kuro-ffi.el     # FFI wrapper functions
└── kuro-renderer.el # Render loop (30fps)
```

## Data Flow

```
┌─────────────┐     PTY      ┌─────────────┐
│   Shell     │◄────────────►│  Rust Core  │
└─────────────┘   Output     └──────┬──────┘
                                    │
                              FFI Bridge
                              (~100ns)
                                    │
                           ┌────────▼────────┐
                           │  Emacs Lisp UI  │
                           │   (Render Loop) │
                           └─────────────────┘
```

## Key Design Decisions

### FFI vs IPC

**Choice**: FFI (emacs-module-rs)

**Rationale**:
- ~100ns latency vs ~10-50μs for IPC
- Single .so file deployment
- Simpler error handling
- No process lifecycle management

**Trade-off**: Rust panic can crash Emacs (mitigated with catch_unwind)

### Dirty Line Tracking

**Approach**: Only update changed lines in Emacs buffer

**Rationale**:
- Reduces Emacs buffer modifications
- Minimizes redisplay overhead
- O(D*C) vs O(R*C) where D = dirty lines

**Implementation**: `dirty_set: HashSet<usize>` in Screen

### Threaded PTY Reading

**Approach**: Dedicated thread reads PTY, sends to main via channel

**Rationale**:
- Non-blocking PTY I/O
- Prevents render loop blocking
- Clean separation of concerns

### user-ptr Pattern

**Approach**: Store Grid reference in Emacs user-ptr

**Rationale**:
- Minimize Lisp object allocations
- Reduce Emacs GC pressure
- Direct memory access without serialization

## Performance Targets

| Metric | Target | Approach |
|--------|--------|----------|
| Parse throughput | >100MB/s | vte crate table-driven parser |
| Grid updates | >1M cells/s | In-memory Vec operations |
| FFI call latency | <1μs | Direct function calls |
| Render time | <16ms/frame | Dirty line tracking, adaptive throttling |
| Memory | <10MB base | Efficient data structures |

## Security Considerations

- All PTY input is untrusted: validate in VTE parser
- FFI boundary: catch_unwind prevents panic propagation
- Resource limits: Configurable scrollback caps
- Memory safety: Rust prevents entire classes of vulnerabilities
