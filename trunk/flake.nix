{
  description = ''Utilities for working with the Encoding for Robust Immutable Storage (ERIS)'';

  inputs.flakeNimbleLib.owner = "riinr";
  inputs.flakeNimbleLib.ref   = "master";
  inputs.flakeNimbleLib.repo  = "nim-flakes-lib";
  inputs.flakeNimbleLib.type  = "github";
  inputs.flakeNimbleLib.inputs.nixpkgs.follows = "nixpkgs";
  
  inputs.src-eris_utils-trunk.flake = false;
  inputs.src-eris_utils-trunk.ref   = "trunk";
  inputs.src-eris_utils-trunk.owner = "~ehmry";
  inputs.src-eris_utils-trunk.repo  = "eris_utils";
  inputs.src-eris_utils-trunk.type  = "sourcehut";
  
  inputs."eris".owner = "nim-nix-pkgs";
  inputs."eris".ref   = "master";
  inputs."eris".repo  = "eris";
  inputs."eris".dir   = "0_7_1";
  inputs."eris".type  = "github";
  inputs."eris".inputs.nixpkgs.follows = "nixpkgs";
  inputs."eris".inputs.flakeNimbleLib.follows = "flakeNimbleLib";
  
  inputs."tkrzw".owner = "nim-nix-pkgs";
  inputs."tkrzw".ref   = "master";
  inputs."tkrzw".repo  = "tkrzw";
  inputs."tkrzw".dir   = "v0_1_2";
  inputs."tkrzw".type  = "github";
  inputs."tkrzw".inputs.nixpkgs.follows = "nixpkgs";
  inputs."tkrzw".inputs.flakeNimbleLib.follows = "flakeNimbleLib";
  
  outputs = { self, nixpkgs, flakeNimbleLib, ...}@deps:
  let 
    lib  = flakeNimbleLib.lib;
    args = ["self" "nixpkgs" "flakeNimbleLib" "src-eris_utils-trunk"];
    over = if builtins.pathExists ./override.nix 
           then { override = import ./override.nix; }
           else { };
  in lib.mkRefOutput (over // {
    inherit self nixpkgs ;
    src  = deps."src-eris_utils-trunk";
    deps = builtins.removeAttrs deps args;
    meta = builtins.fromJSON (builtins.readFile ./meta.json);
  } );
}