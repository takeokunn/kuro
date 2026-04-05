# Kuro shell integration autoload for Fish
# Sourced automatically via XDG_DATA_DIRS when kuro prepends etc/ to it.

string match -q '*kuro*' "$INSIDE_EMACS"; or return

# Resolve the main integration script relative to this vendor_conf.d file.
set -l this_dir (status dirname)
set -l integration_script (string replace '/fish/vendor_conf.d' '' -- $this_dir)/kuro-shell.fish

if test -f $integration_script
    source $integration_script
end
