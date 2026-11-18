# The pool is places outside a home, shortest first and then alphabetical.
#
# The documentation's examples use this convention, and a real hodon should
# pick another.  Every name in it is a location, and the Naming section of
# USAGE.org says why that fails.  The examples use it because nobody racks a
# server on a balcony, so the names read as fiction.  A reader who likes the
# idea meets this warning first.
{
  hodon.hostnames = {
    convention = "home";
    pool = [
      "barn"
      "coop"
      "deck"
      "lawn"
      "pond"
      "shed"
      "yard"
      "arbor"
      "grove"
      "hutch"
      "lanai"
      "patio"
      "porch"
      "stoop"
      "garden"
      "gazebo"
      "kennel"
      "meadow"
      "balcony"
      "carport"
      "firepit"
      "orchard"
      "paddock"
      "pergola"
      "terrace"
      "trellis"
      "veranda"
      "driveway"
      "boathouse"
      "breezeway"
      "courtyard"
      "playhouse"
      "treehouse"
      "greenhouse"
    ];
  };
}
