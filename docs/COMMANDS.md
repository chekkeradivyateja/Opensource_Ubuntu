# Command reference (Ubuntu 24.04)

Every command for this flow on one page: Verilog (`.v`), SystemVerilog (`.sv`) and UVM,
from compile to simulation, waveforms, coverage, synthesis and reports.
Longer explanations: [USER_GUIDE.md](USER_GUIDE.md).

Rules for all sections:
- Open a **new terminal** after `python3 install.py` (it puts the tools on PATH).
- Copy and paste commands; do not retype them.
- Work on a **copy** of an example (or your own folder), not inside the repository folder.
- None of these commands delete anything. Verilator rebuilds only what changed, so there is no need
  to delete `obj_dir/` before compiling again. Never type `rm -rf` with `~`.

| Tool | Command | Used for |
|---|---|---|
| Icarus Verilog 13.0 | `iverilog`, `vvp` | Verilog simulation (4-state: X and Z) |
| Verilator 5.054 | `verilator`, `verilator_coverage` | lint, SystemVerilog/UVM simulation, assertions, coverage |
| Yosys 0.33 | `yosys` | synthesis, cell count, schematics, FSM extraction |
| Graphviz | `dot` | draws schematics and FSM diagrams (SVG) |
| Surfer 0.7.0, GTKWave | `surfer`, `gtkwave` | waveforms (VCD, FST) |
| lcov | `genhtml` | HTML coverage report |
| gvim | `gvim` | editor with Verilog/SystemVerilog colours |

---

## 1. Check the tools

    verilator --version          # Verilator 5.054
    iverilog -V 2>&1 | head -n 1 # Icarus Verilog version 13.0
    yosys -V
    dot -V                       # graphviz version 2.43.0
    which surfer gtkwave gvim genhtml
    echo $UVM_HOME               # /opt/eda/open_ver_flow/uvm-2020.3.1-vlt-656f20d-patched/src

---

## 2. Verilog files (`.v`): Icarus Verilog

Example: `examples/seq_det` (design `rtl/seq_det.v`, testbench `tb/seq_det_tb.v`).

    mkdir -p ~/work && cp -r ~/Opensource_Ubuntu/examples/seq_det ~/work/
    cd ~/work/seq_det

| Step | Command |
|---|---|
| Edit | `gvim rtl/seq_det.v &` |
| Compile (list the files) | `iverilog -g2012 -o sim.out rtl/seq_det.v tb/seq_det_tb.v` |
| Compile (let Icarus find modules in folders) | `iverilog -g2012 -s seq_det_tb -y rtl -y tb -Y .v -o sim.out tb/seq_det_tb.v` |
| Simulate | `vvp -n sim.out \| tee sim.log` |
| Pass/fail | `grep -E "PASS\|FAIL\|ERROR" sim.log` |
| Waveform (testbench calls `$dumpfile("dump.vcd")` and `$dumpvars`) | `surfer dump.vcd &` or `gtkwave dump.vcd &` |
| Lint the design | `verilator --lint-only -Wall rtl/seq_det.v` |

- `-g2012` lets Icarus read SystemVerilog-2012 features (`logic`, `always_ff`, `int`, ...).
- `-s <module>` names the top module; `-y <folder>` + `-Y .v`: a module is found in the file with its name.
- Icarus shows X and Z values; Verilator (sections 3-4) is 2-state and shows them as 0.
- Waveforms need these lines in the testbench (in an `initial` block):

      $dumpfile("dump.vcd");
      $dumpvars(0, seq_det_tb);

**Code coverage for Verilog** (Icarus has no coverage; Verilator compiles the same files):

    verilator --binary --coverage -Wno-fatal --top-module seq_det_tb rtl/seq_det.v tb/seq_det_tb.v
    ./obj_dir/Vseq_det_tb
    verilator_coverage --report summary coverage.dat
    verilator_coverage --annotate cov_annot coverage.dat      # uncovered lines start with %
    verilator_coverage --write-info coverage.info coverage.dat
    genhtml coverage.info --output-directory cov_html
    xdg-open cov_html/index.html

**Synthesis** (cell count, netlist):

    yosys -p "read_verilog rtl/seq_det.v; synth -top seq_det; stat; write_verilog -noattr seq_det_synth.v" | tee synth.log

Look for the cell list and `Number of cells` near the end of `synth.log`.

**Schematics** (Yosys writes a `.dot` file, Graphviz draws it):

    yosys -q -p "read_verilog rtl/seq_det.v; prep -top seq_det; show -format dot -prefix seq_det_rtl seq_det"
    dot -Tsvg seq_det_rtl.dot -o seq_det_rtl.svg          # RTL schematic
    yosys -q -p "read_verilog rtl/seq_det.v; synth -top seq_det; show -format dot -prefix seq_det_gate seq_det"
    dot -Tsvg seq_det_gate.dot -o seq_det_gate.svg        # gate-level schematic
    xdg-open seq_det_rtl.svg

**FSM state diagram** (Yosys extracts the state machine, Graphviz draws it):

    yosys -q -l fsm_report.txt -p "read_verilog rtl/seq_det.v; proc; opt_expr; opt_clean; fsm_detect; fsm_extract; fsm_opt; fsm_info; fsm_export -origenc -o seq_det.kiss2"
    { echo 'digraph fsm { rankdir=LR;'
      awk '/^\./{next} NF==4{print "\"" $2 "\" -> \"" $3 "\" [label=\"" $1 "\"];"}' seq_det.kiss2
      echo '}'; } > seq_det_fsm.dot
    dot -Tsvg seq_det_fsm.dot -o seq_det_fsm.svg
    xdg-open seq_det_fsm.svg

States are shown by their encoding; each arrow is labelled with the input value that takes it. If `seq_det.kiss2` is
empty, Yosys found no FSM: write the next-state logic as a `case` on the state register with a
`default: next = state;` line (see `rtl/seq_det.v`).

---

## 3. SystemVerilog files (`.sv`): Verilator

Example: `examples/counter` (design `rtl/counter.sv`, testbench `tb/tb_top.sv` with an assertion).

    mkdir -p ~/work && cp -r ~/Opensource_Ubuntu/examples/counter ~/work/
    cd ~/work/counter

| Step | Command |
|---|---|
| Edit | `gvim tb/tb_top.sv &` |
| Lint the design | `verilator --lint-only -Wall rtl/counter.sv` |
| Lint design + testbench | `verilator --lint-only --timing --top-module tb_top rtl/counter.sv tb/tb_top.sv` |
| Compile (assertions, coverage, waves) | `verilator --binary --assert --coverage --trace -Wno-fatal -DDUMP_WAVES --top-module tb_top rtl/counter.sv tb/tb_top.sv` |
| Simulate (default test) | `./obj_dir/Vtb_top \| tee sim.log` |
| Simulate another test, with a seed | `./obj_dir/Vtb_top +TEST1 +verilator+seed+5 \| tee test1.log` |
| Pass/fail | `grep -E "PASS\|%Error\|%Warning" sim.log` |
| Waveform | `surfer waves.vcd &` or `gtkwave waves.vcd &` |
| Synthesis | `yosys -p "read_verilog -sv rtl/counter.sv; synth -top counter; stat" \| tee synth.log` |

- `--binary` builds the simulator `obj_dir/V<top>` (includes `--timing` for `#` delays and `@` events).
- `--assert` enables `assert`/`assert property`; a failure prints `%Error: ... Assertion failed` and stops.
  Add `+verilator+error+limit+100` to the run to continue after failures.
- `--trace` allows VCD; use `--trace-fst` for smaller FST files (name the file `waves.fst`).
- `-D<NAME>` defines a macro (here `DUMP_WAVES`, used by the testbench to call `$dumpfile`).
- File order: packages before the files that `import` them; the top testbench last.
- Your own plusargs: `+NAME=value` in the command, `$value$plusargs`/`$test$plusargs` in the testbench.

**Coverage** (code + covergroups + cover properties). Run each test with its own file, then merge:

    ./obj_dir/Vtb_top        +verilator+coverage+file+t0.dat
    ./obj_dir/Vtb_top +TEST1 +verilator+coverage+file+t1.dat
    verilator_coverage --write merged.dat t0.dat t1.dat
    grep -v verilated_std.sv merged.dat > design.dat         # drop Verilator's built-in std package
    verilator_coverage --report summary design.dat           # totals: line, toggle, branch, covergroup, ...
    verilator_coverage --report hier design.dat > cov_report.txt
    verilator_coverage --annotate cov_annot design.dat
    verilator_coverage --filter-type covergroup --annotate cg_bins --annotate-points design.dat   # every bin
    verilator_coverage --write-info coverage.info design.dat
    genhtml coverage.info --output-directory cov_html
    xdg-open cov_html/index.html

The HTML report shows line coverage; the text report (`--report summary`) has all coverage types.
A bigger example with SVA, covergroups and constrained random: `examples/sv_project` (USER_GUIDE sections 2-7).

---

## 4. UVM: Verilator + the UVM library

Example: `examples/uvm_project` (design, interface, package with all UVM classes, top).

    mkdir -p ~/work && cp -r ~/Opensource_Ubuntu/examples/uvm_project ~/work/
    cd ~/work/uvm_project/sim

**Compile** (first time about 2-4 minutes and up to about 3 GB RAM; later builds are faster):

    printf '`verilator_config\ncoverage_off -file "%s/*"\n' "$UVM_HOME" > uvm_cov_off.vlt
    verilator --binary --vpi --assert --coverage --trace -Wno-fatal -Wno-lint -Wno-style -j 1 \
      --timescale 1ns/1ps +incdir+$UVM_HOME +incdir+../tb uvm_cov_off.vlt \
      $UVM_HOME/uvm_pkg.sv ../rtl/alu.sv ../tb/alu_if.sv ../tb/alu_pkg.sv ../tb/tb_top.sv \
      $UVM_HOME/dpi/uvm_dpi.cc --top-module tb_top

- Order: `uvm_pkg.sv` first, then design, interface, your package, top module; `uvm_dpi.cc` last.
- For your own files: replace the five file names; keep everything else.
- `uvm_cov_off.vlt` keeps the UVM library out of the coverage report.

**Run**:

| Step | Command |
|---|---|
| Run a test | `./obj_dir/Vtb_top +UVM_TESTNAME=alu_smoke_test +UVM_NO_RELNOTES \| tee smoke.log` |
| Seed, verbosity, waves, coverage file | `./obj_dir/Vtb_top +UVM_TESTNAME=alu_random_test +UVM_VERBOSITY=UVM_LOW +verilator+seed+3 +verilator+coverage+file+random.dat +WAVES \| tee random.log` |
| Pass/fail | `grep -E "TEST PASSED\|TEST FAILED\|UVM_ERROR :\|UVM_FATAL :" random.log` |
| Waveform (the example's `tb_top` dumps on `+WAVES`) | `surfer waves.vcd &` |
| Coverage | same commands as section 3 (`--write`, `grep -v verilated_std.sv`, `--report`, `genhtml`) |

A UVM test passes when the log shows `UVM_ERROR :    0`, `UVM_FATAL :    0` and `TEST PASSED`.
`+UVM_VERBOSITY=UVM_LOW|UVM_MEDIUM|UVM_HIGH` controls how many `uvm_info` messages are printed.

---

## 5. Projects with a Makefile (recommended for more than a few files)

Copy a template into your project's `sim/` folder, edit the `EDIT HERE` block, then `make help`.

| Template | For | Try it in |
|---|---|---|
| `makefile_templates/sv/Makefile` | SystemVerilog + SVA + covergroups | `examples/sv_project/sim` |
| `makefile_templates/uvm/Makefile` | UVM | `examples/uvm_project/sim` |
| `makefile_templates/Makefile` | smallest: tests `TC1`, `TC2` selected by `+TEST1`, `+TEST2` | `examples/counter/sim` |

| Task | `sv/` and `uvm/` templates | simple template |
|---|---|---|
| Show tools and source files | `make check` | `make check` |
| Lint | `make lint` (UVM testbench: `make lint_tb`) | `make lint` |
| Compile | `make build` | `make build` |
| Run one test | `make run TEST=<name>` (options `SEED=5 WAVES=1 WAVE_FMT=fst PLUSARGS="+N=500"`; UVM also `VERBOSITY=UVM_HIGH`) | `make TC1` (`WAVES=1` for waves) |
| Run all tests | `make regress` (prints `REGRESSION PASSED`/`FAILED`) | `make regress` |
| Coverage report (text) | `make cov` -> `cov_report.txt`, `cov_annot/`, `cov_covergroup/` | `make covtxt` |
| Coverage report (HTML) | `make covhtml`, then `make covopen` | `make covhtml` |
| Waveform | `make waves TEST=<name>` (Surfer), `make gtkwave TEST=<name>` | `gtkwave waves.vcd` |
| Synthesis | `make synth` -> `synth.log` | - |
| Delete generated files | `make clean` (only files the Makefile made) | `make clean` |

Typical day with a project:

    cd ~/work/sv_project/sim
    make lint
    make regress
    make cov
    make covhtml && make covopen
    make run TEST=random WAVES=1 && make waves TEST=random

---

## 6. Everyday commands

| Task | Command |
|---|---|
| Where am I / what is here | `pwd`, `ls -l` |
| Go to a folder / back / home | `cd <folder>`, `cd ..`, `cd ~` |
| Make a folder | `mkdir -p ~/work/my_design` |
| Copy a file / folder | `cp a.sv b.sv`, `cp -r src_folder dst_folder` |
| Rename or move away (instead of deleting) | `mv old_name new_name` |
| Read a long log | `less sim.log` (`/word` to search, `q` to quit) |
| Find errors in a log | `grep -n -E "Error\|FAIL" sim.log` |
| Open an SVG/HTML file | `xdg-open file.svg` |
| Edit | `gvim file.sv &` (or `vi file.sv` in the terminal) |
| Stop a running simulation | `Ctrl+C` |

For VCS/Questa users: `vcs`/`vlog` -> `verilator --binary` (or `iverilog` for Verilog), `./simv` ->
`./obj_dir/V<top>`, `+ntb_random_seed=<n>`/`-sv_seed <n>` -> `+verilator+seed+<n>` (1..2147483647),
`urg`/`vcover report` -> `verilator_coverage` + `genhtml`, Verdi/DVE -> Surfer or GTKWave,
FSDB/VPD/WLF -> VCD/FST. Differences: [USER_GUIDE.md section 11](USER_GUIDE.md#11-differences-from-vcs--questa--verdi).
