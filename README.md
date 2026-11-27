# Open-Source Verification Flow

A free replacement for the paid verification flow (VCS, Questa, Verdi), for training:
SystemVerilog simulation, SVA, code and functional coverage, constrained random and UVM
on Ubuntu, with one installer.

## Tools installed

| Tool | Version | Used for | Installed from |
|---|---|---|---|
| Verilator | 5.054 | lint, compile and simulate SystemVerilog/UVM, assertions (SVA), code + functional coverage, VCD/FST waves | `packages/` (prebuilt) |
| verilator_coverage | 5.054 (part of Verilator) | merge coverage of several tests, text reports, export to lcov | `packages/` |
| UVM library | 2020.3.1 (verilator/uvm commit 656f20d, 2 patches) | UVM class library for testbenches | `packages/` |
| Surfer | 0.7.0 | waveform viewer (VCD, FST) | `packages/` (official release) |
| Icarus Verilog | 13.0 | Verilog simulation (4-state, X/Z), VCD/FST waves | `packages/` (built from v13_0) |
| GTKWave | 3.3.116 | second waveform viewer; `fst2vcd` converter | apt |
| lcov (genhtml) | 2.0 | HTML coverage report | apt |
| Yosys | 0.33 | synthesis check of the RTL, cell count, schematics | apt |
| Graphviz | 2.42.2 (`dot -V` says 2.43.0) | draws schematics and FSM diagrams (SVG/PNG/PDF) | apt |
| gvim | 9.1 (`vim-gtk3`) | editor with Verilog/SystemVerilog colours | apt |
| z3 | 4.8.12 | constraint solver used by `randomize()` | apt |
| g++ | 13.2 | compiles the C++ model that Verilator generates | apt |
| make | 4.3 | runs the Makefiles | apt |
| ccache | 4.9.1 | caches compiled files, so rebuilds (especially UVM) are fast | apt |
| zlib1g-dev, liblz4-dev | Ubuntu 24.04 versions | libraries needed for FST waveforms | apt |
| python3, perl | 3.12, 5.38 | used by Verilator and the installer (already part of Ubuntu) | apt |

Versions of apt packages are the Ubuntu 24.04 versions on the test date; Ubuntu
updates may raise them slightly. Licenses: see `licenses/`.

## Requirements
- Ubuntu 24.04 LTS (any 24.04.x), x86-64. Ubuntu 22.04 is not supported (the tools need glibc 2.38 or newer); the installer offers to upgrade.
- RAM: 8 GB recommended (a UVM compile needs about 3 GB), 4 GB minimum.
- Disk: 3 GB free. Internet for the apt packages. A user with sudo rights.

## Install (step by step)
Copy and paste each command; do not retype it. None of the steps delete anything.
If you cloned it before as `~/Opensource_Ubuntu`, update it with `cd ~/Opensource_Ubuntu && git pull`.
The repository was renamed from `OpenSource_Ubuntu_Ver`: if you have a folder with that old name,
rename it (`mv ~/OpenSource_Ubuntu_Ver ~/OpenSource_Ubuntu_Ver.old`) and follow the steps below.
Never use `rm -rf` with `~`: one extra space (`rm -rf ~/ folder`) deletes your whole home folder.

1. Open a terminal (Ctrl+Alt+T).
2. Install git, if it is not installed yet:

        sudo apt update && sudo apt install -y git

3. Download this repository and run the installer:

        cd ~
        git clone https://github.com/chekkeradivyateja/Opensource_Ubuntu.git
        cd Opensource_Ubuntu
        python3 install.py

4. Answer the questions: your sudo password, then `Y` to install the missing apt packages.
   It takes about 3-7 minutes and ends with `ALL PASSED`.
5. **Close the terminal and open a new one** (this loads the new PATH).
6. Check:

        verilator --version          # Verilator 5.054 2026-11-01 rev v5.054
        echo $UVM_HOME               # /opt/eda/open_ver_flow/uvm-2020.3.1-vlt-656f20d-patched/src
        cd ~/Opensource_Ubuntu/examples/sv_project/sim && make regress    # REGRESSION PASSED

Installer options: `python3 install.py --check` (only check, changes nothing),
`--uvm-test` (also compile and run a UVM test, about 4 minutes more), `--uninstall`.
The installer writes `install.log` in the repository folder.

## How to use the tools
- **[docs/USER_GUIDE.md](docs/USER_GUIDE.md)**: tested commands for simulation, waves, SVA,
  code coverage, functional coverage, constrained random, UVM and Yosys, plus the Makefile
  templates for your own projects.
- **[docs/SV_UVM_SUPPORT.md](docs/SV_UVM_SUPPORT.md)**: what Verilator 5.054 supports, what it
  does differently from VCS/Questa, and tested rewrites for unsupported code.

## Status
| Item | Status |
|---|---|
| Verilator 5.054: lint, simulation, assertions, coverage, VCD | tested on 2026-11-19 with Verilator 5.054, one machine |
| Verilator 5.054: FST waveforms, UVM | FST tested on 2026-11-19; UVM: examples/uvm_project and a UVM feature test on 2026-11-20; one machine |
| Installer (install.py) | install on one Ubuntu 24.04.5 machine: self-test 8/8 PASS incl. UVM (2026-11-19); fresh-machine install not tested yet |
| Makefile template (simple, examples/counter) | tested on 2026-11-20 with Verilator 5.054, one machine |
| Makefile templates sv/ and uvm/ with examples/sv_project and uvm_project | all targets incl. failure detection tested on 2026-11-20 with Verilator 5.054, one machine |
| docs/USER_GUIDE.md commands | all run on 2026-11-20 with Verilator 5.054, one machine |
| Icarus Verilog 13.0, Graphviz, gvim (packages/scripts/test_new_tools.sh) | tested on 2026-11-27 on one Ubuntu 24.04 machine: 30 of 31 checks passed, the 1 FAIL was a wrong check in the test (fixed); installer with these tools: not run yet |
| docs/SV_UVM_SUPPORT.md (docs/support_tests) | 83 SystemVerilog tests + 1 UVM test pass on 2026-11-20, one machine |

## Folders
- install.py  one-command installer (Python standard library only)
- installer/  installer notes
- packages/  prebuilt Verilator 5.054, patched UVM library, Surfer v0.7.0, Icarus Verilog 13.0;
  `packages/scripts/` maintainer build/test scripts
- makefile_templates/  `sv/Makefile` (SystemVerilog project), `uvm/Makefile` (UVM project), `Makefile` (simple, used by examples/counter)
- examples/  `counter` (smallest example), `sv_project` (SVA, covergroups, constrained random), `uvm_project` (UVM)
- docs/  user guide, SV/UVM support guide with its tests, assertions, coverage, status report
- licenses/  license files of the tools

## Limits compared with VCS/Questa/Verdi
2-state simulation (no X/Z), no assertion status in waveforms, no UCDB/VDB coverage
database or GUI coverage browser (the text report combines code, covergroup and
cover-property coverage; the HTML report shows line coverage only).
See docs/SV_UVM_SUPPORT.md and docs/USER_GUIDE.md section 11.

## Problems
Open an Issue (the form asks for the details needed) and attach `install.log`.
Installer messages and fixes: [installer/README.md](installer/README.md).
