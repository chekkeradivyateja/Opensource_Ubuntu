# Status Report

What has been tested in this flow, and what has not. Only results that were actually run
are listed as tested. All tests: Verilator 5.054, Ubuntu 24.04.5 LTS x86-64, one machine
(4 cores, 7.5 GB RAM), unless stated otherwise.

## Tested

| Date | Item | Result |
|---|---|---|
| 2026-11-19 | Verilator 5.054: lint, simulation, assertions, code coverage, VCD | pass |
| 2026-11-19 | FST waveforms (`--trace-fst`, decoded with `fst2vcd`) | pass |
| 2026-11-19 | UVM library (verilator/uvm 656f20d, 2 patches): minimal test | pass; first compile 4 min 30 s, peak RAM 2.9 GB |
| 2026-11-19 | `install.py` on this machine, after removing the tools: check, apt install, unpack, `~/.bashrc`, self-test 8/8 incl. UVM | pass; 6 min 18 s, +3.0 GB RAM peak, about 300 MB disk |
| 2026-11-19 | `install.py` `--check`, second run, `--uninstall`, checksum error, Ubuntu 22.04 message (simulated) | pass |
| 2026-11-19 | trainee machine with Ubuntu 22.04.2: installer stops with the Ubuntu FAIL line, nothing changed | as designed |
| 2026-11-20 | second machine with Ubuntu 22.04.5: checks correct (Ubuntu and Python FAIL, yosys/gtkwave TODO); upgrade answered yes, `do-release-upgrade` ended without upgrading but the installer said "Upgrade finished" | bug found and fixed: the installer now re-checks the version; answers are logged |
| 2026-11-20 | safety review of every delete: `install.py` deletes only checked folders inside `/opt/eda/open_ver_flow` and its own `/tmp` self-test folder, refuses links and outside paths, backs up `~/.bashrc`, removes only its exact marked block; simple Makefile `clean` keeps user `*.dat`/`*.log`; `run_tests.sh` rejects unsafe names and missing files | pass (unit tests, install/re-run/uninstall in a temp folder, self-test, 83/83 support tests) |
| 2026-11-20 | Makefile templates `sv/`, `uvm/` and the simple `Makefile` with their examples: every target, and failure detection with a bug injected in the design | pass |
| 2026-11-20 | every command in `USER_GUIDE.md` | pass |
| 2026-11-20 | `SV_UVM_SUPPORT.md`: 83 SystemVerilog tests + 1 UVM test in `support_tests/` | 84/84 pass (also confirmed on a fresh clone from GitHub) |
| 2026-11-27 | Icarus Verilog 13.0 built and installed with `packages/scripts/build_iverilog.sh` (source SHA-256 checked); the script stopped before packing (fixed; `--pack-only` added) | built; packing and the final `test_new_tools.sh` run pending |

UVM library patches (in `src/base/uvm_component.svh`):
`bit clone;` -> `bit clone_flag;` and `wrapper.clone = clone;` -> `wrapper.clone_flag = clone;`.

## Not tested yet
- `install.py` with Icarus 13.0, Graphviz and gvim added (self-test has 4 new checks).
- `install.py` on a **fresh** Ubuntu 24.04 machine (planned).
- The Ubuntu 22.04 -> 24.04 upgrade offered by the installer (the commands were only simulated).
- Opening Surfer, GTKWave or the browser from `make waves` / `make covopen` on another machine.
- UVM without the two patches.
- The items in `SV_UVM_SUPPORT.md` section 6.

## Known limits
See `SV_UVM_SUPPORT.md` (2-state simulation, SVA limits, coverage limits) and
`USER_GUIDE.md` section 11.

## How to report a problem
Open an Issue on the repository and attach `install.log` or the log of the failing command.
