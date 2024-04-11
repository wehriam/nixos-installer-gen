{ system, nixpkgs, includeBusybox, inputs, config }:
let
  pkgs = import nixpkgs { inherit system; };
in

{
  environment.systemPackages = with pkgs; [ perl perlPackages.JSON nix.perl-bindings python3 config.nix.package ];
  system.extraDependencies = [ (pkgs.mkShell { buildInputs = with pkgs; [ perl perlPackages.JSON nix.perl-bindings python3 config.nix.package ]; }) ];
  isoImage.contents =
    let
      # Because the busybox executable (the builder for bootstrap tools) can be run, it doesn't have the hash type "flat",
      # so nix doesnt fetch it like a tarball (ie through hashed-mirrors). This means we have to add it to the iso here,
      # symlink it in the bash script that sets up the tarball mirror and redirect tarballs.nixos.org to localhost
      busybox-source = (import nixpkgs { inherit system; }).stdenv.bootstrapTools.builder;
      target = builtins.replaceStrings [ "http://tarballs.nixos.org" ] [ "" ] busybox-source.url;
      busybox = { source = busybox-source; target = target; };

      registry = map (dep: { target = "/registry/" + dep.narHash; source = dep; }) inputs;

    in
    registry ++
    nixpkgs.lib.optional includeBusybox busybox;

  # Service that replicates https://tarballs.nixos.org but only for the tarballs used by nixos
  systemd.services.fake-online = {
    description = "Create a fake network interface that tricks nix into think we're online";
    path = [ pkgs.iproute2 ];
    serviceConfig.User = "root";
    serviceConfig.Type = "oneshot";
    script = ''
      ip link add dummy type dummy
      ip addr add 192.168.5.1 dev dummy
    '';
  };

  systemd.services.mirror-tarballs-symlinks = {
    description = "Create symlinks for mirroring tarballs";
    path = [ pkgs.nix pkgs.bash config.nix.package ];
    serviceConfig.User = "tarball-mirror";
    serviceConfig.Type = "oneshot";
    after = [ "fake-online.service" ];
    requires = [ "fake-online.service" ];
    script = ''
      rm -rf ~/tarballs
      mkdir ~/tarballs
      mkdir ~/tarballs/{md5,sha1,sha256,sha512}
      ln -s /iso/stdenv-linux ~/tarballs/stdenv-linux
      cd ~/tarballs
      export NIX_PATH="nixpkgs=/iso/registry/${nixpkgs.narHash}"
      /etc/gen-symlinks.pl
    '';
  };

  systemd.services.mirror-tarballs-server = {
    description = "Serve tarballs on localhost:8000";
    path = [ pkgs.python3 pkgs.bash pkgs.nix config.nix.package ];
    serviceConfig.User = "tarball-mirror";
    serviceConfig.Type = "simple";
    after = [ "mirror-tarballs-symlinks.service" ];
    requires = [ "mirror-tarballs-symlinks.service" ];
    wantedBy = [ "multi-user.target" ];
    script = ''
      cd ~/tarballs/
      python3 -m http.server 8000 --bind 127.0.0.1
    '';
  };

  users.extraUsers.tarball-mirror = {
    description = "Tarball mirrorring user";
    home = "/home/tarball-mirror";
    isNormalUser = true;
  };

  nix.extraOptions = "hashed-mirrors = localhost";
  networking.hosts = { "127.0.0.1" = [ "tarballs.nixos.org" ]; };

  # Redirect port 8000 to port 80 so non root users can use it
  networking.firewall.extraCommands =
    "iptables -t nat -I OUTPUT -p tcp -d 127.0.0.1 --dport 80 -j REDIRECT --to-ports 8000";
}
