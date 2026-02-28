# Kuro - Modern Terminal Emulator for Emacs

Kuro is a high-performance terminal emulator for Emacs, written in Rust with Emacs Lisp UI.

## Features

- **Performance**: >100MB/s parse rate, <1μs FFI calls, <16ms/frame rendering
- **VTE Compliance**: VT100/VT220 compatible (80% vttest pass target)
- **Unicode**: Full CJK support, grapheme clusters, emoji
- **Integration**: Native Emacs integration with theme support

## Installation

### Requirements

- Emacs 29.0 or later
- Rust 1.80 or later
- Linux, macOS, or Windows (WSL2)

### From Source

```bash
git clone https://github.com/takeokunn/kuro.git
cd kuro
make build
make install
```

### MELPA (Coming Soon)

```elisp
M-x package-install RET kuro RET
```

## Quick Start

```elisp
(require 'kuro)
(kuro-create "bash")
```

## Status

**Phase 1** (Weeks 1-7): Foundation + FFI ⏳ In Progress
- [x] Project setup
- [x] Core data structures
- [x] VTE parser integration
- [x] PTY management
- [x] FFI bridge
- [x] Elisp renderer
- [ ] Integration testing
- [ ] Performance validation

**Phase 2** (Weeks 8-20): VTE Compliance + Integration 📅 Planned
**Phase 3** (Weeks 21-27): Advanced Features 📅 Planned
**Phase 4** (Weeks 28-48): Testing & Polish 📅 Planned

## Architecture

Kuro uses the **Remote Display Model**:
- **Rust Core**: Logic, state, VTE parsing, PTY management
- **Emacs Lisp**: Display and view layer only
- **FFI Bridge**: Direct function calls (~100ns overhead)

See [docs/architecture.md](docs/architecture.md) for details.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT License - see [LICENSE](LICENSE)

## Acknowledgments

- Inspired by [emacs-libvterm](https://github.com/akermu/emacs-libvterm)
- Uses [vte](https://github.com/alacritty/vte) for VT parsing
- Uses [emacs-module-rs](https://github.com/ubolonton/emacs-module-rs) for FFI
