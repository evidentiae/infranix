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
        specialArgs ? {},
        system
      }: eval (inputs.nixpkgs.lib.evalModules {
        specialArgs = specialArgs // { inherit inputs; };
        modules = modules ++ [
          ( inputs.nixpkgs + "/nixos/modules/misc/nixpkgs.nix" )
          { nixpkgs.system = system; }
        ];
      });

      integer = import lib/integer.nix;

      ipv4 = import lib/ipv4.nix;

      strings = import lib/strings.nix;

    };

  };
}
