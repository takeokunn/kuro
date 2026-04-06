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

  # Rust formatting is handled exclusively by `checks.kuro-fmt` (crane/cargoFmt
  # with the fenix stable toolchain).  Enabling rustfmt here would use the
  # nixpkgs rustfmt, which may differ from the fenix version and cause
  # treefmt-check and kuro-fmt to produce conflicting outputs.
}
