# PocketFlash

An openFPGA utility for backing up and updating GBA cartridges on Analogue
Pocket.

- Back up cartridge ROMs and saves to the SD card.
- Flash a supplied `.gba` image, with full-ROM verification.
- Compare the cartridge ROM against a selected image.

Supports the **GL-S 32 MiB ROM / SST39VF010 128 KiB save board**.
Other cartridge boards are unsupported. Tested with PocketOS 2.5.
Save restoration is not included.

## Build

Install Nix/devenv and a container runtime: Apple `container` on macOS or Podman
on Linux. Quartus runs in the pinned container image; no local Quartus installation
is required.

```sh
devenv shell
make setup
make toolchain
make test
make rom
```

Without Nix/devenv, install **Python 3.9+** and **GNU Make**, plus **Icarus Verilog**
(`iverilog` and `vvp`) for `make test`. Use the same container runtime and run the
`make` commands above directly, skipping `devenv shell`.

Tests run sequentially by default. Use `make test TEST_JOBS=4` (or
`make test-hdl TEST_JOBS=4`) to run up to four HDL benches concurrently. Each
bench's output is grouped with its duration; failures and timeouts fail the suite.

The installable ZIP is `dist/pocketflash-0.2.0-beta.1-candidate.zip`.

GitHub Actions runs the test suite with four HDL workers on pushes and pull
requests, with manual runs also available from the Actions tab. The **Build core**
workflow runs manually only, to avoid pulling the large Quartus image on every
change. It uses the pinned
image, checks timing, and uploads the installable ZIP as the `pocketflash-utility`
artifact. Quartus reports are available in `quartus-reports`, including after
failed builds when reports exist.

## Use

1. With Pocket powered off, extract the ZIP to the SD card root, merging its
   folders, and insert the cartridge. Launch **PocketFlash** from openFPGA.
2. Use **Up/Down** to choose an action, **A** to select, **B** to go back or cancel,
   and **X** for details.
3. Choose **Backup ROM** or **Backup Saves** to create verified backups in
   `/Saves/pocketflash/common/`. Filenames increment automatically.
4. To flash or verify, select your `.gba` file using **Target ROM** in Pocket's
   menu. Images must be 192 bytes to 32 MiB, with a size divisible by four.
5. Choose **Flash ROM**, acknowledge the prompt, then release and hold **A** for
   two seconds when instructed. Wait for **ROM VERIFIED** before powering off.
   **Verify ROM** compares the cartridge against the selected file without writing.

Flashing replaces the entire ROM, filling unused space with FF, and preserves
save memory. Keep your own ROM and save backups. During flashing, **B** stops
after the current sector; an interrupted flash requires a complete reflash.

See the [user guide](docs/user-guide.md) for details and troubleshooting.

## License

Original code is MIT licensed. See [LICENSE](LICENSE) and
[NOTICE.md](NOTICE.md) for upstream attribution.
