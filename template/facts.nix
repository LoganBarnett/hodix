# The hodon.  Everything hodix runs is derived from this file.
{
  hodon = {
    name = "home";
    defaultHost = "balcony";
    networks.main.ipv4 = {
      cidr = "10.10.0.0/24";
      # The router.  It keeps carrying the network to the Internet.
      gateway = "10.10.0.1";
    };
    hosts.balcony = {
      system = "x86_64-linux";
      interfaces.main = {
        ipv4.address = "10.10.0.9";
        # The machine's hardware address.  ip link in the installer prints it.
        macAddresses = [ "00:00:5e:00:53:01" ];
      };
    };
    users.ada = {
      fullName = "Ada Lovelace";
      groups = [ "family" ];
    };
    groups.family = { };
  };
  hodix = {
    tls.root.subject = {
      country = "US";
      state = "Oregon";
      location = "Portland";
    };
  };
}
