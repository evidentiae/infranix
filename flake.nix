{
  description = "infranix";

  outputs = {self}: {

    overlay = import ./nixpkgs;

    overlays = [ self.overlay ];

    lib = {

      evalModulesWithInputs = {
        eval ? (x: x),
        inputs,
        modules ? [],
        pkgs ? null,
        specialArgs ? {},
        system
      }: eval (inputs.nixpkgs.lib.evalModules {
        specialArgs = specialArgs // { inherit inputs; };
        modules = modules ++ [
          ( inputs.nixpkgs + "/nixos/modules/misc/nixpkgs.nix" )
          {
            nixpkgs = {
              inherit system;
            } // (if pkgs == null then {} else {
              inherit pkgs;
            });
          }
        ];
      });

      integer = import lib/integer.nix;

      ipv4 = import lib/ipv4.nix;

      strings = import lib/strings.nix;

    };

  };
}
