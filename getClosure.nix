lib:
with lib;
target:
let
  canEval = val: (builtins.tryEval val).success;
  rootDrvsIn = x:
    if !canEval x then [ ]
    else if isDerivation x then optional (canEval x.drvPath) x
    else if isList x then concatLists (map rootDrvsIn x)
    else if isAttrs x then concatLists (mapAttrsToList (n: v: addErrorContext "while finding tarballs in '${n}':" (rootDrvsIn v)) x)
    else [ ];
  keyDrv = drv: { key = drv.drvPath; value = drv; };
  immediateDeps = drv:
    concatLists (mapAttrsToList (n: v: drvsIn v) (removeAttrs drv ([ "meta" "passthru" "inputDerivation" ] ++ optionals (drv?passthru) (attrNames drv.passthru))));
  drvsIn = x:
    if !canEval x then [ ]
    else if isDerivation x then optional (canEval x.drvPath) x
    else if isList x then concatLists (map drvsIn x)
    else [ ];
  closureFor = pkg: map (x: x.value) (genericClosure {
    startSet = map keyDrv (rootDrvsIn pkg);
    operator = { key, value }: map keyDrv (immediateDeps value);
  });
in
closureFor target
