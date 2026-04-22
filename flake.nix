{
  description = "NixOS/nix stable release with NixOS/nix#15638 (darwin Mach-O page-hash fix) patches pre-applied";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
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
          patched = pkgs.nixVersions.latest.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ patchFiles;
          });
        in
        {
          default = patched;
          nix = patched;
        }
      );
    };
}
