{
  mkQmkFirmware,
  keychron-qmk,
}: let
  keyboard = "keychron/k6_he/ansi";
in {
  qwerty = mkQmkFirmware {
    pname = "k6he-qwerty";
    version = "2025q3";
    src = keychron-qmk;
    inherit keyboard;
    keymap = "qwerty";
    keymapPath = ./keymaps/qwerty;
    artifacts = [
      "bin"
      "hex"
    ];
  };

  colemak = mkQmkFirmware {
    pname = "k6he-colemak";
    version = "2025q3";
    src = keychron-qmk;
    inherit keyboard;
    keymap = "colemak";
    keymapPath = ./keymaps/colemak;
    artifacts = [
      "bin"
      "hex"
    ];
  };
}
