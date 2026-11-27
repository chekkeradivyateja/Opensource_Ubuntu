# Tool packages (Ubuntu 24.04 LTS, x86-64)

| File | Contents | Source |
|---|---|---|
| `verilator-5.054-ubuntu24.04-x86_64.tar.gz` | Verilator 5.054, prebuilt, without debug binaries | https://github.com/verilator/verilator/tree/v5.054 |
| `uvm-2020.3.1-vlt-656f20d-patched.tar.gz` | Verilator UVM library, commit 656f20d, with two patches (below) | https://github.com/verilator/uvm |
| `surfer_linux_v0.7.0.zip` | Surfer v0.7.0, official release file, unchanged | https://gitlab.com/surfer-project/surfer/-/releases/v0.7.0 |
| `iverilog-13.0-ubuntu24.04-x86_64.tar.gz` | Icarus Verilog 13.0, built from the tag archive v13_0 (SHA-256 `c897bbfa9848688982c6d5c30529fc29d68df0b9ff22ffa73bad89db73a7ce49`) by `scripts/build_iverilog.sh` | https://github.com/steveicarus/iverilog/tree/v13_0 |

Check the files with `sha256sum -c SHA256SUMS`.
Licenses are in `../licenses/`.

## Changes from the original sources
- Verilator: the built-in default `VERILATOR_ROOT` in `bin/verilator_bin` and
  the `prefix` in `share/pkgconfig/verilator.pc` are set to
  `/opt/eda/open_ver_flow/verilator-5.054`, where `install.py` installs it.
- UVM, `src/base/uvm_component.svh`:
  `bit clone;` -> `bit clone_flag;` and
  `wrapper.clone = clone;` -> `wrapper.clone_flag = clone;`.

- Icarus Verilog: built with `--prefix=/opt/eda/open_ver_flow/iverilog-13.0` (Icarus has its install
  path built in), source unchanged.

Yosys, z3, lcov, GTKWave, Graphviz and gvim (`vim-gtk3`) are installed from the Ubuntu 24.04 packages (apt).

## Maintainer scripts (`scripts/`)
- `build_iverilog.sh`: builds and packs Icarus Verilog 13.0 (checks the source SHA-256 first).
- `test_new_tools.sh`: tests Icarus, Graphviz and gvim alone and with Yosys before a release.
Trainees do not run these; `install.py` uses the finished packages.
