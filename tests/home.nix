# A valid hodon shared by the test suites.
{
  hodon = {
    name = "home";
    defaultHost = "balcony";
    networks = {
      main = {
        vlanId = 10;
        ipv4 = {
          cidr = "10.10.0.0/24";
          gateway = "10.10.0.1";
        };
      };
      # A tunnel hands out no leases.
      vpn.ipv4 = {
        cidr = "192.168.102.0/24";
        leases = null;
      };
    };
    hosts = {
      balcony = {
        system = "x86_64-linux";
        sshHostKey =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMU/XFNQlmnxjNvEaDkTFNZ5eD7/ScMjx7iTOEG1OL7i root@balcony";
        primaryInterface = "main";
        interfaces = {
          main = {
            ipv4.address = "10.10.0.9";
            macAddresses = [ "00:00:5e:00:53:01" ];
          };
          vpn = {
            ipv4.address = "192.168.102.9";
            device = "wg0";
          };
        };
      };
      patio = {
        system = "aarch64-darwin";
        sshHostKey =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIVg50Q1DPQGdkOUi9mtIpnTzt5InJQckIJTZ++TeEdV root@patio";
        interfaces.main.ipv4.address = "10.10.0.20";
      };
      printer = {
        managed = false;
        interfaces.main.macAddresses = [ "00:00:5e:00:53:02" ];
      };
    };
  };
}
