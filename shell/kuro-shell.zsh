# Kuro shell integration for Zsh
# Emits OSC sequences for directory tracking, prompt marks, and title

[[ "$INSIDE_EMACS" == *kuro* ]] || return

__kuro_osc() {
    printf '\e]%s\e\\' "$1"
}

__kuro_before_prompt() {
    local exit_code=$?
    # Guard: don't emit command-end on the very first prompt (no command ran yet).
    if [[ -n "$__kuro_cmd_executed" ]]; then
        __kuro_osc "133;D;$exit_code"
    fi
    __kuro_cmd_executed=1
    __kuro_osc "7;file://$(hostname)/$(pwd)"
    __kuro_osc "2;$USER@$(hostname):$(pwd)"
    __kuro_osc "133;A"
}

__kuro_after_prompt() {
    __kuro_osc "133;B"
}

__kuro_preexec() {
    __kuro_osc "133;C"
}

if [[ -z "$__kuro_initialized" ]]; then
    __kuro_initialized=1
    __kuro_cmd_executed=
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd __kuro_before_prompt
    add-zsh-hook precmd __kuro_after_prompt
    add-zsh-hook preexec __kuro_preexec

    # Restore ZDOTDIR if it was overridden for integration injection.
    if [[ -n "$KURO_ORIGINAL_ZDOTDIR" ]]; then
        export ZDOTDIR="$KURO_ORIGINAL_ZDOTDIR"
        unset KURO_ORIGINAL_ZDOTDIR
    fi
fi
