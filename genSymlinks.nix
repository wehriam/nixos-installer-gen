{ registry, lib, tarballs }: {
  environment.etc."tarballs.json".text =
    let
      genElem = x: { url = x.url; hash = x.outputHash; type = x.outputHashAlgo; name = x.name; };
      result = map (value: genElem value) tarballs;
    in
    builtins.toJSON result;

  environment.etc."gen-symlinks.pl" = {
    mode = "555";
    text = ''
      #! /usr/bin/env nix-shell
      #! nix-shell -i perl -p perl perlPackages.JSON nix nix.perl-bindings

      # Modified version of nixpkgs/maintainers/scripts/copy-tarballs.pl

      use strict;
      use warnings;
      use JSON;
      use Nix::Store;

      isValidPath("/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-foo"); # FIXME: forces Nix::Store initialisation

      sub makeLinks {
          my ($fn, $name) = @_;

          my $md5_16 = hashFile("md5", 0, $fn) or die;
          my $sha1_16 = hashFile("sha1", 0, $fn) or die;
          my $sha256_32 = hashFile("sha256", 1, $fn) or die;
          my $sha256_16 = hashFile("sha256", 0, $fn) or die;
          my $sha512_32 = hashFile("sha512", 1, $fn) or die;
          my $sha512_16 = hashFile("sha512", 0, $fn) or die;

          symlink($fn, "/home/tarball-mirror/tarballs/md5/$md5_16");
          symlink($fn, "/home/tarball-mirror/tarballs/sha1/$sha1_16");
          symlink($fn, "/home/tarball-mirror/tarballs/sha256/$sha256_32");
          symlink($fn, "/home/tarball-mirror/tarballs/sha256/$sha256_16");
          symlink($fn, "/home/tarball-mirror/tarballs/sha512/$sha512_32");
          symlink($fn, "/home/tarball-mirror/tarballs/sha512/$sha512_16");
      }

      # Evaluate find-tarballs.nix.
      my $pid = open (JSON, "-|", "cat", "/etc/tarballs.json");
      my $stdout = <JSON>;
      waitpid($pid, 0);
      die "$0: evaluation failed\n" if $?;
      close JSON;

      my $fetches = decode_json($stdout);

      print STDERR "evaluation returned ", scalar(@{$fetches}), " tarballs\n";

      # Check every fetchurl call discovered by find-tarballs.nix.
      foreach my $fetch (sort { $a->{url} cmp $b->{url} } @{$fetches}) {
          my $url = $fetch->{url};
          my $algo = $fetch->{type};
          my $hash = $fetch->{hash};
          my $name = $fetch->{name};

          if ($hash =~ /^([a-z0-9]+)-([A-Za-z0-9+\/=]+)$/) {
              $algo = $1;
              $hash = `nix hash to-base16 $hash` or die;
              chomp $hash;
          }

          next unless $algo =~ /^[a-z0-9]+$/;

          # Convert non-SRI base-64 to base-16.
          if ($hash =~ /^[A-Za-z0-9+\/=]+$/) {
              $hash = `nix hash to-base16 --type '$algo' $hash` or die;
              chomp $hash;
          }

          if ($url !~ /^http:/ && $url !~ /^https:/ && $url !~ /^ftp:/ && $url !~ /^mirror:/) {
              print STDERR "skipping $url (unsupported scheme)\n";
              next;
          }

          my $storePath = makeFixedOutputPath(0, $algo, $hash, $name);

          print STDERR "mirroring $url ($storePath, $algo, $hash)...\n";

          if (isValidPath($storePath)) {
              makeLinks($storePath, $url);
          } else {
              print STDERR "missing tarball: $storePath, skipping\n";
          }

      }

    '';
  };
}
