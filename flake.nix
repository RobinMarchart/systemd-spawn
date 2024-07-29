{
  description = "tool that runs a programm in as systemd service in one scope per program";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default-linux";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
      rust-overlay,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };
        inherit (pkgs) lib;
        craneLib = (crane.mkLib pkgs).overrideToolchain (
          p: p.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml
        );
        src = craneLib.cleanCargoSource ./.;
        # Common arguments can be set here to avoid repeating them later
        commonArgs = {
          strictDeps = true;
          inherit src;
        };

        # Build *just* the cargo dependencies, so we can reuse
        # all of that work (e.g. via cachix) when running in CI
        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        # Build the actual crate itself, reusing the dependency
        # artifacts from above.
        systemd-spawn_unwrapped = craneLib.buildPackage (commonArgs // { inherit cargoArtifacts; });
        systemd-spawn = pkgs.writeShellApplication {
          name = "systemd-spawn";
          text = "exec \"${systemd-spawn_unwrapped}/bin/systemd-spawn\"";
        };
      in
      {
        checks = {
          # Build the crate as part of `nix flake check` for convenience
          inherit systemd-spawn systemd-spawn_unwrapped;

          # Run clippy (and deny all warnings) on the crate source,
          # again, reusing the dependency artifacts from above.
          #
          # Note that this is done as a separate derivation so that
          # we can block the CI if there are issues here, but not
          # prevent downstream consumers from building our crate by itself.
          shots-clippy = craneLib.cargoClippy (
            commonArgs
            // {
              inherit cargoArtifacts;
              cargoClippyExtraArgs = "-- --deny warnings";
            }
          );

          shots-doc = craneLib.cargoDoc (commonArgs // { inherit cargoArtifacts; });

          # Check formatting
          shots-fmt = craneLib.cargoFmt { inherit src; };

          shots-nextest = craneLib.cargoNextest (
            commonArgs
            // {
              inherit cargoArtifacts;
              partitions = 1;
              partitionType = "count";
            }
          );
        };

        packages = {
          default = systemd-spawn;
          inherit systemd-spawn_unwrapped;
        };

        apps.default = flake-utils.lib.mkApp { drv = systemd-spawn; };

        devShells.default = craneLib.devShell {
           checks = self.checks.${system};
        };
      }
    );
}
