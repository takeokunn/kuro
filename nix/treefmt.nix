# nix/treefmt.nix — treefmt formatter configuration
#
# Used by:
#   nix fmt                  → formats all files in-place
#   nix flake check          → checks.treefmt verifies nothing is unformatted
#
# To add a new formatter: enable the corresponding programs.* option.
# Full list: https://github.com/numtide/treefmt-nix#supported-programs
{ pkgs, ... }: {
  projectRootFile = "flake.nix";

  programs.nixfmt = {
    enable = true; # Nix — nixfmt-classic (use `nix fmt` for Nix files only)
    package = pkgs.nixfmt-classic;
  };
  # Rust formatting is handled by `nix flake check` (kuro-fmt via crane's cargoFmt),
  # not by treefmt, to avoid edition-mismatch with standalone rustfmt.
}
