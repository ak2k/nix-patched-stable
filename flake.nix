{
  description = "NixOS/nix stable release with NixOS/nix#15638 (darwin Mach-O page-hash fix) patches pre-applied";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Track NixOS/nix at a specific stable tag. Bumped by bump-stable.yml.
    nix-upstream.url = "github:NixOS/nix/2.34.6";
  };

  outputs =
    { self, nixpkgs, nix-upstream }:
    let
      # The Mach-O page-hash fix is darwin-only (`#ifdef __APPLE__`), so
      # shipping an aarch64-linux build just burns CI cycles. Upstream
      # nix's aarch64-linux test suite also happens to be unreliable
      # under GHA's ubuntu-24.04-arm runner (fchmodatTryNoFollow), but
      # that's secondary — the core reason is "no consumer".
      systems = [
        "aarch64-darwin"
      ];
      forAllSystems =
        f: builtins.listToAttrs (map (system: { name = system; value = f system; }) systems);
      patchFiles = [
        ./patches/0001-libstore-Bit-reproducibly-fix-darwin-Mach-O-page-has.patch
        ./patches/0002-libstore-Harden-darwin-Mach-O-fixup-for-fat64-dual-C.patch
      ];
      # nix-upstream's embedded flake.lock pins nixpkgs as a channel tarball
      # (https://releases.nixos.org/...). The flake-compat shim used by
      # `import patchedSrc` reads that lock and calls builtins.fetchTree on
      # it — which requires a live HTTPS download even when the content is
      # already in the store. Replace it with a github: entry pointing at our
      # own nixpkgs input so evaluation never needs a network fetch.
      nixpkgsLocked = builtins.toJSON {
        lastModified = nixpkgs.lastModified;
        narHash = nixpkgs.narHash;
        owner = "NixOS";
        repo = "nixpkgs";
        rev = nixpkgs.rev;
        type = "github";
      };
      nixpkgsOriginal = builtins.toJSON {
        owner = "NixOS";
        ref = "nixos-unstable";
        repo = "nixpkgs";
        type = "github";
      };
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
              # Rewrite nix-upstream's embedded flake.lock: replace the
              # channel-tarball nixpkgs with a github: entry so that
              # `import patchedSrc` (flake-compat shim) never needs to
              # fetch from nixos.org at eval time.
              ${pkgs.jq}/bin/jq \
                --argjson locked '${nixpkgsLocked}' \
                --argjson original '${nixpkgsOriginal}' \
                '.nodes.nixpkgs.locked = $locked | .nodes.nixpkgs.original = $original' \
                flake.lock > flake.lock.tmp
              mv flake.lock.tmp flake.lock
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
