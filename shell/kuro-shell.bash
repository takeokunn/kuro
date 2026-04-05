# Kuro shell integration for Bash
# Emits OSC sequences for directory tracking, prompt marks, and title

[[ "$INSIDE_EMACS" == *kuro* ]] || return

__kuro_osc() {
    printf '\e]%s\e\\' "$1"
}

__kuro_prompt_start() {
    __kuro_osc "133;A"
}

__kuro_prompt_end() {
    __kuro_osc "133;B"
}

__kuro_command_start() {
    __kuro_osc "133;C"
}

__kuro_command_end() {
    __kuro_osc "133;D;$1"
}

__kuro_cwd() {
    __kuro_osc "7;file://$(hostname)/$(pwd)"
}

__kuro_title() {
    __kuro_osc "2;$USER@$(hostname):$(pwd)"
}

__kuro_before_prompt() {
    local exit_code=$?
    # Guard: don't emit command-end on the very first prompt (no command ran yet).
    if [[ -n "$__kuro_cmd_executed" ]]; then
        __kuro_command_end "$exit_code"
    fi
    __kuro_cmd_executed=1
    __kuro_cwd
    __kuro_title
}

if [[ -z "$__kuro_initialized" ]]; then
    __kuro_initialized=1
    __kuro_cmd_executed=
    PROMPT_COMMAND="__kuro_before_prompt${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
    PS1="\[$(__kuro_prompt_start)\]${PS1}\[$(__kuro_prompt_end)\]"
    # PS0 fires exactly once per interactive command (cleaner than DEBUG trap
    # which fires for every simple command including completions and PROMPT_COMMAND).
    PS0="\[$(__kuro_command_start)\]"
fi
