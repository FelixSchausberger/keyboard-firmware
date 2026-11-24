{
  pkgs,
  mkQmkFirmware,
  keychron-qmk,
}: let
  keyboard = "keychron/k6_he/ansi";

  src = pkgs.fetchFromGitHub {
    owner = "Keychron";
    repo = "qmk_firmware";
    inherit (keychron-qmk) rev;
    fetchSubmodules = true;
    hash = "sha256-lIAOZp0JOd6ZqCU2Irzbp38ZIb6L3b5XrfiOalUeQOI=";
  };
in {
  qwerty = mkQmkFirmware {
    pname = "k6he-qwerty";
    version = "2025q3";
    inherit src keyboard;
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
    inherit src keyboard;
    keymap = "colemak";
    keymapPath = ./keymaps/colemak;
    artifacts = [
      "bin"
      "hex"
    ];
  };
}
