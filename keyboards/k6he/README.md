# Keychron K6 HE ANSI

The K6 HE is a 65% Hall-effect keyboard with a STM32F401, USB-C, 2.4 GHz and
Bluetooth. The firmware comes from Keychron's QMK fork (`Keychron/qmk_firmware`,
branch `2025q3`), which carries the analog (HE) matrix, wireless and RGB
drivers that upstream QMK does not have.

- Keyboard target: `keychron/k6_he/ansi`
- MCU: `STM32F401`
- Bootloader: `stm32-dfu` (`0483:df11`)
- Normal-mode USB ID: `3434:0e60`
- Layout: `LAYOUT_ansi_68` (65%, 68 keys)

## Build

```bash
nix build .#k6he           # QWERTY, default
nix build .#k6he-colemak   # Colemak-DH letter block, Keychron layers intact
```

The artifacts are installed at the root of the result:

- `keychron_k6_he_ansi_qwerty.bin` / `.hex`
- `keychron_k6_he_ansi_colemak.bin` / `.hex`

Both packages use the same pinned Keychron tree (flake input `keychron-qmk`,
locked to the `2025q3` branch, submodules included). No network access happens
during the build; `nix build --offline` works once the input is in the store.

`lib/mkQmkFirmware.nix` does the generic work: copy the QMK tree to a writable
directory, inject `keyboards/k6he/keymaps/<name>` at
`keyboards/keychron/k6_he/ansi/keymaps/<name>`, run `make` with `BUILD_DIR`
outside the source tree, and install the requested artifacts.

## Keymaps

`qwerty` is the Keychron stock `keychron` keymap with two maintenance keys
added on the `FN2` layer:

- `FN2 + Enter`: `QK_BOOT` (reboot into the STM32 DFU bootloader)
- `FN2 + Home`: `EE_CLR` (clear the EEPROM, including the dynamic keymap)

`colemak` is the same keymap with the Colemak-DH matrix applied to the Mac and
Win base layers. The Fn layers, wireless keys (`BT_HST1..3`, `P2P4G`), RGB
keys and media keys are unchanged.

`RGB_MATRIX_SLEEP` is already enabled upstream in
`keyboards/keychron/k6_he/info.json` (`"rgb_matrix": { "sleep": true }`), so no
keymap-level override is needed.

## Flash

```bash
nix run .#flash-k6he -- ./result/keychron_k6_he_ansi_qwerty.bin
```

1. Set the mode switch to **Cable**.
2. Disconnect USB-C.
3. Hold **Esc** (or press the reset button under the space bar) and plug the
   USB-C cable in. The keyboard enumerates as STM32 DFU (`0483:df11`).
4. Run the command above. The script refuses to run unless exactly one STM32
   DFU device is present, so it cannot guess between multiple boards.

The udev rules for the STM32 bootloader come from
`hardware.keyboard.qmk.enable = true` on the host. For non-root access to the
keyboard in normal mode (VIA, Keychron Launcher), also set
`hardware.keyboard.qmk.keychronSupport = true`; that host configuration is not
managed by this repository.

## EEPROM, HE calibration and wireless pairing

The compiled keymap is only the default. VIA and Keychron Launcher store the
live keymap in the keyboard's EEPROM, and flashing new firmware does not
overwrite it. After flashing:

- If the old keymap is still active, press `FN2 + Home` (`EE_CLR`) to clear the
  EEPROM and load the compiled keymap.
- `EE_CLR` also resets the HE calibration and the Bluetooth pairing data.
  Recalibrate the HE keys and re-pair the host(s) in Keychron Launcher.
- Export the Launcher keymap/HE settings and confirm the stock-firmware restore
  path **before** the first custom flash. The Launcher can reflash the stock
  firmware; keep that rollback available.
- The 2.4 GHz/Bluetooth module has separate firmware and is not touched by the
  main MCU DFU flash. A failed main-firmware flash does not brick the wireless
  side.

## VIA, Vial and Launcher

Keychron's `keychron` keymap has `VIA_ENABLE = yes`, so the custom keymaps are
VIA keymaps. Keychron Launcher is the supported tool for HE actuation, rapid
trigger and wireless configuration. Vial is not supported by the official
Keychron tree; a third-party fork (`EKl41/vial-qmk`, branch
`vial-updated-keychron`) carries a Vial keymap for this board, but it lags
Keychron's `2025q3` fixes and is not used here.

## Rollback

1. Disconnect the custom firmware or enter DFU as above.
2. Use Keychron Launcher's firmware update to restore the stock firmware, or
   flash the stock `.bin` for the K6 HE with `dfu-util`.
3. Recalibrate HE keys and re-pair wireless hosts if the EEPROM was cleared.

## Notes

- Do not use the `keychron` keymap from the upstream tree directly as the
  repository default: the firmware would silently change when the pinned
  `2025q3` input is updated. The `qwerty` copy makes the default explicit.
- The `.bin` is the DFU artifact. The `.hex` is provided for
  STM32CubeProgrammer-style flashing; `flash-k6he` uses the `.bin`.
