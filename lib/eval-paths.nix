paths:

with builtins;

with (
  let t = typeOf paths;
  in if t == "string" then {
    pathsFile = paths;
    pathAttrs = import paths;
  } else if t == "path" then {
    pathsFile = toString paths;
    pathAttrs = import paths;
  } else if t == "set" && paths ? type && paths.type == "derivation" then rec {
    pathsFile = toString paths;
    pathAttrs = import pathsFile;
  } else if t == "set" && paths ? outPath then rec {
    pathsFile = toString paths;
    pathAttrs = import pathsFile;
  } else if t == "set" then {
    pathsFile = null;
    pathAttrs = paths;
  } else throw "paths argument has wrong type"
);

let

  evalPath = name:
    let
      p = pathAttrs.${name};
      t = typeOf p;
    in {
      inherit name;
      value =
        if t == "string" || t == "path" then
          { path = p; pathRef = p; }
        else if t == "set" && p ? url then
          let p' = fetchGit p; in {
            path = toString p';
            pathRef = p // { inherit (p') rev; };
          }
        else throw "path attribute ${name} has an unsupported type";
    };

    pathNames = attrNames pathAttrs;

    pathAttrs' = listToAttrs (map evalPath pathNames);

    paths' = listToAttrs (map (name: {
      inherit name;
      value = pathAttrs'.${name}.path;
    }) pathNames) // {
      _refs = listToAttrs (map (name: {
        inherit name;
        value = pathAttrs'.${name}.pathRef;
      }) pathNames);
      _pathsFile = pathsFile;
    };

in paths'
