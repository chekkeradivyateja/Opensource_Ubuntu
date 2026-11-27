# Installer (`install.py`)

The installer is `../install.py` (Python standard library only). Run it from the
repository folder as your normal user, **not** with sudo:

    cd ~/Opensource_Ubuntu
    python3 install.py              # check, install, self-test
    python3 install.py --uvm-test   # same + compile and run a UVM test (about 4 minutes more)
    python3 install.py --check      # only check the machine; changes nothing
    python3 install.py --uninstall  # remove the installed tools and the ~/.bashrc block

Everything printed, and your answers to its questions, is also written to `install.log` in the
repository folder.

## What it does, step by step
1. **Checks** the machine. Every line shows what was found, what is required and, if needed,
   how to fix it, for example:

       PASS  Ubuntu: found Ubuntu 24.04.5 LTS; required Ubuntu 24.04.x LTS
       WARN  RAM: found 7.4 GB; required 8 GB recommended, 4 GB minimum. Fix: ...
       TODO  apt yosys: found not installed; required installed. Fix: will be installed (you will be asked)
       INFO  Other Verilator: found Verilator 5.020 at /usr/bin/verilator. Note: it is kept; ...

   Checked: Ubuntu 24.04.x, x86-64 CPU, Python 3.12+, RAM, 3 GB free disk, normal user,
   `sudo`, apt not busy, checksums of the files in `packages/`, each apt package, internet
   (only when apt packages are missing), other Verilator installations.
   If any check is `FAIL`, nothing is changed.
2. **Ubuntu 22.04 or older**: prints the upgrade commands and asks
   `Upgrade Ubuntu to 24.04 now? [y/N]` (default No). Back up first; on a lab machine
   ask the administrator. Afterwards it checks the Ubuntu version again and says whether the
   upgrade really happened. After the upgrade and reboot, run `install.py` again.
3. **sudo**: asks for your password once.
4. **apt packages**: lists the missing ones and asks `Install them now? [Y/n]`.
   Packages: `yosys z3 lcov gtkwave g++ make perl python3 ccache zlib1g-dev liblz4-dev`.
   If you answer No, it prints the exact command to run yourself and stops.
5. **Unpacks** Verilator 5.054, the patched UVM library and Surfer 0.7.0 from `../packages/`
   into `/opt/eda/open_ver_flow/` (the folder is created once with sudo and owned by you).
6. **Environment**: adds this block at the end of `~/.bashrc` (replaced, not duplicated, on a re-run):

       # >>> open_ver_flow >>>
       export VERILATOR_ROOT=/opt/eda/open_ver_flow/verilator-5.054/share/verilator
       export UVM_HOME=/opt/eda/open_ver_flow/uvm-2020.3.1-vlt-656f20d-patched/src
       export PATH=/opt/eda/open_ver_flow/verilator-5.054/bin:/opt/eda/open_ver_flow/surfer-0.7.0:$PATH
       # <<< open_ver_flow <<<

7. **Self-test** in a temporary folder with `examples/counter`: lint, simulation + assertions,
   coverage + lcov, FST waveform, Yosys synthesis, tool versions (UVM compile and run with
   `--uvm-test`). Ends with `ALL PASSED`. **Open a new terminal** afterwards.

## What it never touches
Your projects, source files, logs, waveforms, Downloads, and other tool installations.
An older Verilator (for example Ubuntu's 5.020 or one in your home folder) is kept; the new
one comes first in `PATH`. `--uninstall` removes only `/opt/eda/open_ver_flow/*` and the
marked `~/.bashrc` block; apt packages stay.

## What it deletes (and nothing else)
- On a re-install: an old copy of `verilator-5.054`, `uvm-2020.3.1-vlt-656f20d-patched` or
  `surfer-0.7.0` inside `/opt/eda/open_ver_flow/`, before unpacking it again.
- Its own self-test folder in `/tmp` (`open_ver_flow_selftest_*`), only when the self-test passed.
- `--uninstall`: the same 3 tool folders, `/opt/eda/open_ver_flow` itself only if it is then empty,
  and the marked block in `~/.bashrc`.

Every delete is checked first: the folder must really be inside `/opt/eda/open_ver_flow` (or `/tmp`),
otherwise the installer refuses and stops. Before `~/.bashrc` is changed, the previous version is
saved as `~/.bashrc.open_ver_flow.bak`.

**Safety tip:** copy and paste commands; do not retype them. Never type `rm -rf` with `~`: one
extra space (`rm -rf ~/ folder`) deletes your whole home folder. To get rid of an old clone,
rename it instead: `mv ~/Opensource_Ubuntu ~/Opensource_Ubuntu.old`.

## Running it again
Safe: already unpacked packages are skipped (checked by checksum), the `~/.bashrc` block is
replaced, and the self-test runs again.

## Measured on one machine (Ubuntu 24.04.5, 4 cores, 7.5 GB RAM, 2026-11-19, with `--uvm-test`)
| | |
|---|---|
| Time | 6 min 18 s (about 3 min of it is apt download/install) |
| Extra RAM at peak | about 3.0 GB (UVM compile) |
| Disk | about 300 MB installed; about 1.1 GB free needed during the install |

## Troubleshooting
| Message | What to do |
|---|---|
| `FAIL  Ubuntu: found Ubuntu 22.04...` | upgrade to 24.04 (the installer offers it) or install 24.04 fresh |
| `Ubuntu is still 22.04...: the upgrade did not run` | read what `do-release-upgrade` printed (for example "No new release found", or you answered No); fix that, then run again |
| `FAIL  User: ... required normal user` | run `python3 install.py` without `sudo` |
| `FAIL  apt: found busy` | Ubuntu is installing updates; wait a few minutes and run again |
| `FAIL  packages/...: found checksum mismatch` | the download is damaged; rename the folder (`mv ~/Opensource_Ubuntu ~/Opensource_Ubuntu.old`) and clone again |
| `FAIL  Internet: ...` | connect to the internet, or install the listed apt packages another way |
| `FAIL  sudo did not work` | wrong password or no sudo rights; ask your administrator |
| `verilator: command not found` after `ALL PASSED` | open a new terminal |
| a self-test line shows `FAIL` | open a GitHub Issue and attach `install.log` |
