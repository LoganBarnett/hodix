{
  description = "A hodon.";

  inputs.hodix.url = "github:LoganBarnett/hodix";

  outputs =
    { self, hodix, ... }:
    hodix.lib.mkHodon {
      inherit self;
      modules = [ ./facts.nix ];
      hosts = ./hosts;
    };
}
