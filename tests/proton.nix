# A valid hodon shared by the test suites.
{
  hodon = {
    name = "proton";
    networks = {
      main = {
        vlanId = 10;
        ipv4.cidr = "10.10.0.0/24";
      };
      vpn.ipv4.cidr = "192.168.102.0/24";
    };
    hosts = {
      silicon = {
        system = "x86_64-linux";
        sshHostKey =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINKb3dosTnnxqVxmRXk9hM9kOh97Hmce68VWJN5M5Q6C root@silicon";
        primaryInterface = "main";
        interfaces = {
          main = {
            ipv4.address = "10.10.0.9";
            macAddresses = [ "b8:ca:3a:77:a9:2a" ];
          };
          vpn.ipv4.address = "192.168.102.9";
        };
      };
      scandium = {
        system = "aarch64-darwin";
        sshHostKey =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJneX2Ox2J9GxP4ot4K+bw73lZPQdrpVUamNwgmq31aP root@scandium";
        interfaces.main.ipv4.address = "10.10.0.20";
      };
      printer.interfaces.main.macAddresses = [ "ac:19:8e:f6:04:a0" ];
    };
  };
}
