# nix-patched-stable

Upstream NixOS/nix release with the
[NixOS/nix#15638](https://github.com/NixOS/nix/pull/15638) darwin
Mach-O page-hash correction patches pre-applied. Rebuilt daily against
the latest nixpkgs-tracked `nixVersions.latest`, pushed to
[`ak2k.cachix.org`](https://ak2k.cachix.org).

## What it fixes

[`NixOS/nixpkgs#507531`](https://github.com/NixOS/nixpkgs/issues/507531) /
[`NixOS/nix#6065`](https://github.com/NixOS/nix/issues/6065) — the macOS
kernel SIGKILLs multi-output darwin binaries (fish, git, zsh, and others)
when a sibling output is already in the store at rebuild time.
`nix-daemon`'s `RewritingSink` byte-substitutes scratch-path bytes inside
pages that `ld -adhoc_codesign` had already covered with SHA-256 page
hashes; the kernel then refuses to load the binary. The two-commit patch
recomputes only the stale page-hash slots in place after the rewrite,
preserving every other structural field including the `linker-signed`
flag and the original page size.

## Use

```nix
{
  inputs.nix-patched.url = "github:ak2k/nix-patched-stable";

  outputs = { nix-patched, ... }: {
    darwinConfigurations.my-host = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        { nix.package = nix-patched.packages.aarch64-darwin.default; }
        # ...
      ];
    };
  };
}
```

Add the binary cache to avoid rebuilding locally:

```nix
nix.settings.substituters = [
  "https://cache.nixos.org"
  "https://ak2k.cachix.org"
];
nix.settings.trusted-public-keys = [
  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  # Public key for ak2k.cachix.org — copy from https://app.cachix.org/cache/ak2k
];
```

Systems published: `aarch64-darwin`, `aarch64-linux`.

## How it works

- `flake.nix` takes `nixpkgs.legacyPackages.<system>.nixVersions.latest` as
  the base and applies the two patches in `patches/` via `overrideAttrs`.
- `bump-stable.yml` runs daily (06:00 UTC) and on manual dispatch; it does
  `nix flake update nixpkgs` and commits when the pinned nixpkgs advances.
  Any new `nixVersions.latest` bump lands here.
- `build-and-cache.yml` runs on every push to `main`, builds the patched
  nix on `macos-latest` (aarch64-darwin) and `ubuntu-24.04-arm`
  (aarch64-linux), runs `./result/bin/nix --version` as a smoke test, and
  pushes the build closure to `ak2k.cachix.org` via `cachix-action`.

## When this repo goes away

When `NixOS/nix#15638` merges and a Nix release carries the fix,
`nixpkgs.nixVersions.latest` alone will work — this repo becomes unnecessary.
At that point the repo will be archived.
