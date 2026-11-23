# PocketFlash quick guide

PocketFlash supports FMS GBA cartridges with the GL-S 32 MiB ROM / SST39VF010
128 KiB save board. Other boards with the same chips can have different wiring
and are unsupported. Use PocketOS 2.5 or later; 2.5 is the tested baseline. The
package requires openFPGA framework `2.3`, a separate version from PocketOS.
Dock operation is untested. Sleep and save states are disabled.

## Install and prepare

1. Turn Pocket off. Extract the ZIP to the root of its SD card, merging
   the `Cores`, `Assets`, `Platforms` and `Saves` folders.
2. Put your own `.gba` image on the SD card. Insert a cart matching the target board profile with power
   off, then launch **PocketFlash** from openFPGA. Do not change carts with power on.
3. Use Up/Down to select an action, A to select, B to back out/cancel, X for details.
   Select the image through Pocket's menu entry **Target ROM** before Flash or Verify.
   Images must be 192 bytes through 32 MiB, with a size divisible by four.

The core now installs as `Cores/PocketFlash.PocketFlash`. When replacing an older
installation, remove its old PocketFlash folder from `Cores` to avoid duplicate
menu entries. Backups remain in `/Saves/pocketflash/common/`.

Progress appears as `0%` through `100%` for the current stage. Elapsed time is in
seconds (`S`). Flashing shows erase and buffer counts; backups show the output
filenames. X opens CRC, cartridge identity and error details.

## Back up

Choose **Backup ROM** or **Backup Saves**, then press A. Wait for **BACKUP VERIFIED**.
Each file is reopened from SD and compared byte for byte against a second cart
read before a completion record is written and checked. Save backup reads both
64 KiB banks, then restores bank zero. It never programs or erases saves.

Files are in `/Saves/pocketflash/common/`:

|    Action    |      Data      | Completion record |
| ------------ | -------------- | ----------------- |
| Backup ROM   | `rom0001.gba`  | `rom0001.pfr`     |
| Backup Saves | `save0001.sav` | `save0001.pfs`    |

The first unused pair from 0001 through 9999 is selected automatically. An existing
file of either kind reserves the number, including an interrupted backup. Old
`dump1` through `dump3` files are preserved. Keep data and record together; copy
important backups elsewhere. The displayed CRC is useful for comparing captures.
Identical save-bank contents can be legitimate. Save **restoration is not included**.

## Flash a ROM

Manage your own ROM and save backups before flashing. The utility does not require
an original-ROM file or a particular game title. It replaces the entire 32 MiB ROM;
space beyond the selected image is filled with FF. Saves are kept separate.

1. Select **Flash ROM**, press A, read the responsibility acknowledgement, and press
   A again to check the selected image and hardware.
2. When **RELEASE A THEN HOLD A TWO SECONDS** appears, release A, then hold it for
   two seconds. An invalid GBA header is shown as a warning; it does not block
   flashing. Preflight alone does not erase/program the cartridge.
3. Leave Pocket powered until **ROM VERIFIED**. Erases/program counts are decimal.
   The final check covers the entire image and FF padding. A plausible header is
   informational and does not prove an image is safe or suitable for your cart.
4. Choose **Verify ROM** for an independent comparison with the selected image,
   or back up the result for optional host inspection. Power off before booting
   the cartridge normally. Confirm normal application behavior and save persistence.

B requests a stop after the current sector during flashing. A cancelled or failed
flash can leave the ROM incomplete. Reflash a complete known-good image from the
beginning; do not try to resume. The latest selected image remains your choice:
there is no automatic restoration or bundled recovery ROM.

## If something stops

|       Message        | Next action                                                                                                           |
| -------------------- | --------------------------------------------------------------------------------------------------------------------- |
| SD error             | Check the card and free space. Keep partial files; retry allocates a new name.                                        |
| ROM changed          | Select the intended file again, then restart the operation.                                                           |
| Verify/CRC mismatch  | Keep the files and details. Repeat a cold read before trusting a backup. Reflash a known-good ROM if flashing failed. |
| Unsupported profile  | Stop. Matching chip names do not establish compatible wiring.                                                         |
| Power off and reload | Power Pocket fully off, then relaunch. An app reset cannot clear uncertain cartridge state.                           |
| No free backup names | Move archived pairs off SD with Pocket powered off; preserve important backups.                                       |

Report version, firmware, cart origin/chip labels, action, exact message, X-details
and whether the ROM boots. ROMs and saves may contain private data: do not attach
them publicly. The utility cannot guarantee SD durability beyond PocketOS's
acknowledgements and the verified reread.

## Optional computer checks

Python is optional for ordinary operation. Developers can use:

```
python3 tools/pocketflash.py inspect-save /path/to/save0001.sav
python3 tools/pocketflash.py verify-write /path/to/image.gba /path/to/rom0001.gba
```

PFR1 flags 3 from older experiment builds certify SD readback; they do not assert
the additional cartridge comparison introduced by this candidate. PFS1 records
are 16-byte little-endian magic `PFS1`, byte length, CRC32 and flags 3.
