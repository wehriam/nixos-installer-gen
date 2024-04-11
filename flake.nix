{
  description = "Generate an installer for a particular nixos config, with some extra misc utilities";
  outputs = { nixpkgs, ... }: rec {

    lib = {
      getInputs = with builtins; root:
        let
          startSet = [{ key = ""; value = root; }];
          operator = inp: nixpkgs.lib.attrsets.mapAttrsToList (key: value: { key = inp.key + key + "/"; value = value; }) (inp.value.inputs or { });
          closure = genericClosure { inherit startSet operator; };
          filtered = filter (x: x.key != "") closure;
          keyToName = map (x: x // { name = x.key; }) filtered;
        in
        listToAttrs keyToName;

      getTarballs = import ./getTarballs.nix nixpkgs.lib;
      getClosure = import ./getClosure.nix nixpkgs.lib;
    };

    generateInstaller =
      { includeSrc ? false
      , includeUnzipped ? false
      , includeBusybox ? true
      , # Include the bootstrap busybox (nixpkgs.stdenv.bootstrapTools.builder)
        modules ? [ ]
      , targetConfig ? nixpkgs.lib.nixosSystem { inherit system; }
      , inputFlake ? null
      , system ? "x86_64-linux"
      }:
      let
        args = {
          inherit includeSrc includeUnzipped includeBusybox modules targetConfig inputFlake system;
        };

        inputSet = lib.getInputs (if inputFlake == null then { inputs = { }; } else inputFlake);
        pkgs = (import nixpkgs { inherit system; });

        resultModules = modules ++ [
          (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
          {
            isoImage.contents = nixpkgs.lib.optional (inputFlake != null) {target = "/configs/"; source = inputFlake;};
            boot.kernelPackages = pkgs.zfs.latestCompatibleLinuxPackages;
            # Breaks ventoy
            hardware.cpu.intel.updateMicrocode = nixpkgs.lib.mkImageMediaOverride false;
            system.extraDependencies = with targetConfig.config.system;
              [
                path
                build.toplevel
              ] ++ extraDependencies;
            passthru = {
              sources = tarballs;
              inputs = inputSet;
              inherit args;
              override = overrides: generateInstaller (args // overrides);
            };
          }
        ];

        sourcelessResult = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = resultModules;
        };

        tarballs = lib.getTarballs {
          root = [ targetConfig.config.system.build.toplevel targetConfig.config.environment.systemPackages ];
          inherit includeUnzipped includeBusybox;
        };
        tarballsList = pkgs.writeText "tarballs-list" (builtins.concatStringsSep "\n" tarballs);
        sourceResult = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = resultModules ++ [
            (import ./tarballServer.nix {
              inherit system nixpkgs includeBusybox;
              inputs = builtins.attrValues inputSet;
              config = sourcelessResult.config;
            })
            (import ./genSymlinks.nix {
              registry = inputSet;
              lib = nixpkgs.lib;
              inherit tarballs;
            })
            { system.extraDependencies = [ tarballsList ]; }
          ];
        };

      in
      assert builtins.compareVersions sourcelessResult.config.nix.package.version "2.11.0" >= 0;
      # Nix version must be 2.11 or higher (due to a bug where nix-shell depends on bashinteractive-dev)
      # The specific fix is https://github.com/NixOS/nix/commit/5f37c5191a3a8f5c7ab31a0dd8bffe14aaa6b76c
      rec {
        result = if includeSrc then sourceResult else sourcelessResult;
        iso = result.config.system.build.isoImage;
        sources = tarballs;
        inputs = inputSet;
        inherit args;
        override = overrides: generateInstaller (args // overrides);
      };

    baseInstaller = system: nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [ (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix") ];
    };
  };
}
