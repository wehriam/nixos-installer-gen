lib: { includeUnzipped ? false
     , includeBusybox ? true
     , root
     }:
with lib;
let
  closureFor = import ./getClosure.nix lib;

  # Filter non-fetchurl deps
  urlOf = pkg: pkg.url or (builtins.head pkg.urls);
  isBootstrapBusybox = pkg: (builtins.baseNameOf (urlOf pkg)) == "busybox" && (builtins.substring 0 26 (urlOf pkg)) == "http://tarballs.nixos.org/";
  tarballsFor = pkg: filter
    (drv:
      drv.outputHash or "" != "" &&
      (drv ? url || drv ? urls) &&
      ((drv.outputHashMode or "flat" == "flat") ||
      includeUnzipped ||
      (isBootstrapBusybox drv && includeBusybox)) &&
      (drv.postFetch or "" == "" || includeUnzipped)
    )
    (closureFor pkg);
  urlsFor = pkg: map (drv: drv // { url = drv.url or (head drv.urls); }) (tarballsFor pkg);
  unique = target: map (x: x.value) (genericClosure {
    startSet = map (x: { key = x.drvPath; value = x; }) target;
    operator = const [ ];
  });
  uniqueUrlsFor = pkg: unique (urlsFor pkg);

in
uniqueUrlsFor root
