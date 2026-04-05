# Kuro shell integration for Fish
# Emits OSC sequences for directory tracking, prompt marks, and title

string match -q '*kuro*' "$INSIDE_EMACS"; or return

function __kuro_osc
    printf '\e]%s\e\\' $argv[1]
end

function __kuro_prompt --on-event fish_prompt
    set -l exit_code $status
    # Guard: don't emit command-end on the very first prompt (no command ran yet).
    if set -q __kuro_cmd_executed
        __kuro_osc "133;D;$exit_code"
    end
    set -g __kuro_cmd_executed 1
    __kuro_osc "7;file://"(hostname)"/"(pwd)
    __kuro_osc "2;$USER@"(hostname)":"(pwd)
    __kuro_osc "133;A"
    __kuro_osc "133;B"
end

function __kuro_preexec --on-event fish_preexec
    __kuro_osc "133;C"
end
