{
  description = "NixOS/nix stable release with NixOS/nix#15638 (darwin Mach-O page-hash fix) patches pre-applied";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Track NixOS/nix at a specific stable tag. Bumped by bump-stable.yml.
    nix-upstream.url = "github:NixOS/nix/2.34.5";
  };

  outputs =
    { self, nixpkgs, nix-upstream }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
      ];
      forAllSystems =
        f: builtins.listToAttrs (map (system: { name = system; value = f system; }) systems);
      patchFiles = [
        ./patches/0001-libstore-Bit-reproducibly-fix-darwin-Mach-O-page-has.patch
        ./patches/0002-libstore-Harden-darwin-Mach-O-fixup-for-fat64-dual-C.patch
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          patchedSrc = pkgs.applyPatches {
            name = "nix-patched-src";
            src = nix-upstream;
            patches = patchFiles;
            # Tag `nix --version` so a user running this daemon can tell
            # at a glance that it's patched, rather than confusing it with
            # stock upstream. `+` is semver build-metadata.
            postPatch = ''
              echo "$(cat .version)+ak2k-mach-o-fix" > .version
            '';
          };
          # Re-evaluate nix-upstream's flake on the patched source via the
          # flake-compat shim its `default.nix` already sets up. This avoids
          # the `getFlake ... store-path` restriction.
          patchedFlake = import patchedSrc;
        in
        {
          default = patchedFlake.packages.${system}.default;
          nix = patchedFlake.packages.${system}.nix;
        }
      );
    };
}
