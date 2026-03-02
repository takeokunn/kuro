# Configuration Guide

This guide explains all user-configurable options for the kuro terminal emulator.
All settings are defined as `defcustom` variables in `kuro-config.el` and
integrate with Emacs' standard `M-x customize` interface.

## Quick Start

Open the kuro customization group:

```
M-x customize-group RET kuro RET
```

Validate your current settings:

```
M-x kuro-validate-config
```

## Core Settings

### `kuro-shell`

Shell program to run in the Kuro terminal.

| Property | Value |
|----------|-------|
| Default | `$SHELL` environment variable, or `/bin/bash` |
| Type | String (executable path) |
| Group | `kuro` |

The shell must be accessible via `PATH`. Setting a path to a non-existent
executable signals a `user-error`. The variable `kuro-default-shell` is a
backward-compatibility alias for `kuro-shell`.

```elisp
(setq kuro-shell "/bin/zsh")
```

### `kuro-scrollback-size`

Maximum number of lines retained in the scrollback buffer.

| Property | Value |
|----------|-------|
| Default | `10000` |
| Type | Positive integer (> 0) |
| Group | `kuro` |

Changes take effect immediately in all running Kuro buffers.

```elisp
(setq kuro-scrollback-size 20000)
```

## Display Settings

### `kuro-frame-rate`

Frame rate for terminal rendering, in frames per second.

| Property | Value |
|----------|-------|
| Default | `30` |
| Type | Positive integer (> 0) |
| Group | `kuro-display` |

Changes take effect immediately by restarting the render loop in all
active Kuro buffers.

```elisp
(setq kuro-frame-rate 60)
```

### `kuro-font-family`

Font family for Kuro terminal buffers.

| Property | Value |
|----------|-------|
| Default | `nil` (inherit from default face) |
| Type | String or `nil` |
| Group | `kuro-display` |

Only effective in graphical Emacs frames; no effect in terminal frames.
Changes apply immediately via `face-remap-add-relative`.

```elisp
(setq kuro-font-family "Iosevka")
```

### `kuro-font-size`

Font size in points for Kuro terminal buffers.

| Property | Value |
|----------|-------|
| Default | `nil` (inherit from default face) |
| Type | Positive integer in points, or `nil` |
| Group | `kuro-display` |

Only effective in graphical Emacs frames. Internally converted to Emacs
face `:height` units (`(* 10 value)`), so `14` becomes `:height 140`.

```elisp
(setq kuro-font-size 14)
```

## ANSI Color Palette

All 16 ANSI terminal colors are individually customizable. Each variable
accepts a 6-digit hex color string in `#rrggbb` format. Color changes
rebuild the internal color table and clear the face cache immediately.

| Variable | ANSI Index | Default |
|----------|-----------|---------|
| `kuro-color-black` | 0 | `#000000` |
| `kuro-color-red` | 1 | `#c23621` |
| `kuro-color-green` | 2 | `#25bc24` |
| `kuro-color-yellow` | 3 | `#adad27` |
| `kuro-color-blue` | 4 | `#492ee1` |
| `kuro-color-magenta` | 5 | `#d338d3` |
| `kuro-color-cyan` | 6 | `#33bbc8` |
| `kuro-color-white` | 7 | `#cbcccd` |
| `kuro-color-bright-black` | 8 | `#808080` |
| `kuro-color-bright-red` | 9 | `#ff0000` |
| `kuro-color-bright-green` | 10 | `#00ff00` |
| `kuro-color-bright-yellow` | 11 | `#ffff00` |
| `kuro-color-bright-blue` | 12 | `#0000ff` |
| `kuro-color-bright-magenta` | 13 | `#ff00ff` |
| `kuro-color-bright-cyan` | 14 | `#00ffff` |
| `kuro-color-bright-white` | 15 | `#ffffff` |

Example: applying a Solarized-inspired palette:

```elisp
(setq kuro-color-black    "#073642"
      kuro-color-red      "#dc322f"
      kuro-color-green    "#859900"
      kuro-color-yellow   "#b58900"
      kuro-color-blue     "#268bd2"
      kuro-color-magenta  "#d33682"
      kuro-color-cyan     "#2aa198"
      kuro-color-white    "#eee8d5")
```

## Configuration Validation

`M-x kuro-validate-config` checks all settings and reports errors in the
echo area. An empty result means everything is valid. It verifies:

- `kuro-shell`: executable accessible via `PATH`
- `kuro-scrollback-size`: positive integer (> 0)
- `kuro-frame-rate`: positive integer (> 0)
- `kuro-font-size`: positive integer or `nil`
- All 16 `kuro-color-*` variables: 6-digit hex strings in `#rrggbb` format

## `use-package` Example

```elisp
(use-package kuro
  :config
  (setq kuro-shell          "/bin/zsh"
        kuro-scrollback-size 20000
        kuro-frame-rate      60
        kuro-font-family     "Iosevka"
        kuro-font-size       14
        kuro-color-black     "#1e1e2e"
        kuro-color-white     "#cdd6f4")
  :bind ("C-c t" . kuro-create))
```

## Runtime Reconfiguration

All `defcustom` variables support runtime changes via their `:set` handlers.
Changes through `customize-set-variable`, `setopt`, or `M-x customize-group`
take effect immediately:

```elisp
;; Increase scrollback at runtime
(customize-set-variable 'kuro-scrollback-size 50000)

;; Change frame rate at runtime (restarts render loop in all kuro buffers)
(customize-set-variable 'kuro-frame-rate 60)
```

## Related Documentation

- [Installation](./install.md) — Installing kuro
- [Shell Integration](./shell-integration.md) — Shell configuration
