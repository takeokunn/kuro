# nix/treefmt.nix — treefmt formatter configuration
#
# Used by:
#   nix fmt                  → formats all files in-place
#   nix flake check          → checks.treefmt verifies nothing is unformatted
#
# To add a new formatter: enable the corresponding programs.* option.
# Full list: https://github.com/numtide/treefmt-nix#supported-programs
{ ... }:
{
  projectRootFile = "flake.nix";

  # Nix — nixfmt RFC-166 style (modern opinionated formatter)
  programs.nixfmt.enable = true;

  # Rust — rustfmt with project's edition (Cargo.toml drives edition)
  programs.rustfmt.enable = true;
}
