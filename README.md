## Nixos installer generator
Forked from: https://gitlab.com/genericnerdyusername/nixos-installer-gen

Example usage:
```nix
{
installer-iso = let
  main = installer-gen.generateInstaller {
    inputFlake = self;  # Inputs of this flake will be copied to the store to allow offline evaluation
    includeSrc = true;  # Include most tarballs used to compile the closure of targetConfig
    # Most runtime deps of this config will be copied to the installer (some need to be added manually)
    targetConfig = nixosConfigurations.nixos;
    modules = [  # Extra modules to add to the installer
      {
        # Reduce compression. For docs, see
        # https://github.com/NixOS/nixpkgs/blob/50f9b3107a09ed35bbf3f9ab36ad2683619debd2/nixos/lib/make-squashfs.nix#L8
        # or
        # https://github.com/NixOS/nixpkgs/blob/50f9b3107a09ed35bbf3f9ab36ad2683619debd2/nixos/modules/installer/cd-dvd/iso-image.nix#L477
        isoImage.squashfsCompression = "zstd -Xcompression-level 6";
        nixpkgs.config.allowUnfree = true;
      }
      ./misc.nix
    ];
  };
in main.iso;
}
```
