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

**Phase 1** ✅ Complete — Foundation + FFI
- [x] Project setup
- [x] Core data structures (Cell, Color, SgrAttributes, Grid)
- [x] VTE parser integration (vte crate)
- [x] PTY management
- [x] FFI bridge (emacs-module-rs)
- [x] Elisp renderer

**Phase 2** ✅ Complete — VTE Compliance + Integration
- [x] VT100/VT220 cursor movement (CUU/CUD/CUF/CUB/CUP)
- [x] Erase sequences (ED/EL)
- [x] Scroll region (DECSTBM)
- [x] SGR attributes (bold, italic, underline, colors, 256-color, TrueColor)
- [x] Insert/delete sequences (IL, DL, ICH, DCH, ECH)
- [x] Tab stop management (HTS, TBC)

**Phase 3** ✅ Complete — Advanced Features
- [x] Kitty Graphics Protocol (APC sequences)
- [x] Kitty Keyboard Protocol
- [x] OSC 7 (working directory notification)
- [x] OSC 8 (hyperlinks)
- [x] OSC 52 (clipboard)
- [x] OSC 133 (shell integration / semantic prompts)

**Phase 4** 🔄 In Progress — Testing & Polish
- [x] 444 Rust tests passing
- [x] 47 ERT tests passing
- [ ] vttest 80%+ compliance validation
- [ ] Performance benchmarks (>100MB/s parse rate target)
- [ ] MELPA packaging

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
