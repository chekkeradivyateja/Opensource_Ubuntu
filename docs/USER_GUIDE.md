# User Guide: verification with the open-source flow

Every command in this guide was run with Verilator 5.054 on Ubuntu 24.04 (see the
date in the Status table of the main README). The example files used here are in
`examples/sv_project/` (SystemVerilog + SVA + functional coverage) and
`examples/uvm_project/` (UVM).

Contents
1. Before you start
2. SystemVerilog simulation (single files)
3. Waveforms
4. Assertions (SVA)
5. Code coverage
6. Functional coverage (covergroups)
7. Constrained random stimulus
8. UVM
9. Synthesis check with Yosys
10. Makefile templates for your own project
11. Differences from VCS / Questa / Verdi
12. Troubleshooting

---

## 1. Before you start

Open a **new terminal** after running `install.py`, then check:

    verilator --version        # Verilator 5.054 2026-11-01 rev v5.054
    echo $UVM_HOME             # /opt/eda/open_ver_flow/uvm-2020.3.1-vlt-656f20d-patched/src
    which surfer               # /opt/eda/open_ver_flow/surfer-0.7.0/surfer

To follow sections 2-7, copy the example files into an empty folder:

    mkdir -p ~/sv_demo && cd ~/sv_demo
    cp <repo>/examples/sv_project/rtl/alu.sv <repo>/examples/sv_project/sva/alu_sva.sv \
       <repo>/examples/sv_project/tb/alu_tb_pkg.sv <repo>/examples/sv_project/tb/tb_top.sv .

(`<repo>` is the folder where you cloned this repository, for example `~/Opensource_Ubuntu`.)

| File | What it is |
|---|---|
| `alu.sv` | design: 8-bit ALU with registered output |
| `alu_sva.sv` | assertions, attached to the ALU with `bind` |
| `alu_tb_pkg.sv` | package with the random transaction class |
| `tb_top.sv` | testbench: tests `smoke` and `random`, covergroup, checker |

---

## 2. SystemVerilog simulation (single files)

**Lint** (find coding problems without simulating):

    verilator --lint-only -Wall alu.sv
    verilator --lint-only --timing --top-module tb_top alu.sv alu_sva.sv alu_tb_pkg.sv tb_top.sv

No output except the Verilation Report means no warnings. Use `-Wall` on design files.
On testbench code `-Wall` also reports class fields as "not used" even when
`randomize()` uses them, so lint testbenches without `-Wall`.

**Compile** (creates the simulator `obj_dir/Vtb_top`):

    verilator --binary --assert --coverage --trace -Wno-fatal --top-module tb_top \
      alu.sv alu_sva.sv alu_tb_pkg.sv tb_top.sv

| Option | Meaning |
|---|---|
| `--binary` | build a ready-to-run simulator (includes `--timing` for `#` delays and `@` events) |
| `--assert` | enable assertions (SVA and `assert`) |
| `--coverage` | collect line, toggle, branch, expression, covergroup and cover-property coverage |
| `--trace` | allow VCD waveform dumping (`--trace-fst` for FST) |
| `-Wno-fatal` | show warnings but do not stop |
| `--top-module` | name of the top testbench module |

File order matters: a package must come before the files that `import` it.

**Run** a test (the testbench reads `+TEST=<name>`):

    ./obj_dir/Vtb_top +TEST=smoke
    ./obj_dir/Vtb_top +TEST=random +N=300 +verilator+seed+5

Expected end of the output:

    checked=300 errors=0 functional coverage=100.0%
    TEST PASSED

Useful run-time options:

| Option | Meaning |
|---|---|
| `+verilator+seed+<n>` | seed for `randomize()` and `$urandom` |
| `+verilator+coverage+file+<name>.dat` | coverage file name (default `coverage.dat`) |
| `+verilator+error+limit+<n>` | keep running after the first `$error` / assertion failure |
| your own `+NAME=value` | read in the testbench with `$value$plusargs` / `$test$plusargs` |

---

## 3. Waveforms

The testbench decides when to dump waves. `tb_top.sv` does it when `+WAVES` is given:

    if ($test$plusargs("WAVES")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_top);
    end

Run with waves and open them:

    ./obj_dir/Vtb_top +TEST=smoke +WAVES
    surfer waves.vcd          # or: gtkwave waves.vcd

In Surfer, click `tb_top` in the left panel to add its signals.

**FST** (smaller files): compile with `--trace-fst` instead of `--trace`. The file
written by `$dumpfile` is then in FST format; name it `waves.fst`. Surfer and GTKWave open both.

Time units: add `` `timescale 1ns/1ps `` to every file so times show in ns.
Without it Verilator uses 1 ps.

---

## 4. Assertions (SVA)

Assertions are checked only when compiled with `--assert`. `alu_sva.sv` shows the
common forms that work in Verilator 5.054:

    // implication with next-cycle check, disabled during reset
    a_valid_latency: assert property (@(posedge clk) disable iff (!rst_n)
      in_valid |=> out_valid) else $error("out_valid did not follow in_valid");

    // $past for values from the previous cycle
    a_add_ok: assert property (@(posedge clk) disable iff (!rst_n)
      (in_valid && op == 2'd0) |=> result == $past({1'b0, a}) + $past({1'b0, b}));

    // cover property: counted in the coverage report as "user" coverage
    c_back_to_back: cover property (@(posedge clk) disable iff (!rst_n) in_valid ##1 in_valid);

    // attach to every instance of alu without changing the RTL
    bind alu alu_sva u_alu_sva (.*);

Also tested: `|->`, `##n`, `##[m:n]`, `$rose`, named `sequence` and `property`.

**What a failure looks like** (here `out_valid` was broken on purpose):

    [55000] %Error: alu_sva.sv:15: Assertion failed in tb_top.dut.u_alu_sva.a_valid_latency: out_valid did not follow in_valid
    %Error: alu_sva.sv:15: Verilog $stop

The simulation stops at the first failure with exit code 1 and **does not write
coverage**. To continue after failures, add `+verilator+error+limit+100`; the run then
ends with exit code 0, so always search the log for `%Error`.

---

## 5. Code coverage

Compile with `--coverage` (section 2), run one or more tests, each with its own file:

    ./obj_dir/Vtb_top +TEST=smoke  +verilator+coverage+file+smoke.dat
    ./obj_dir/Vtb_top +TEST=random +verilator+coverage+file+random.dat

**Merge** the tests and remove Verilator's built-in `std` package (otherwise it
lowers the numbers as soon as classes or `randomize()` are used):

    verilator_coverage --write merged.dat smoke.dat random.dat
    grep -v verilated_std.sv merged.dat > design.dat

**Text reports:**

    verilator_coverage --report summary design.dat     # totals per coverage type
    verilator_coverage --report hier design.dat        # per instance and per module

Example summary:

    Coverage Summary:
      line       :  83.3% ( 20/ 24)
      toggle     :  98.5% (201/204)
      branch     :  70.0% ( 14/ 20)
      expr       :  86.7% ( 13/ 15)
      covergroup : 100.0% ( 22/ 22)
      user       : 100.0% (  2/  2)

`user` is `cover property`. Look at the `tb_top.dut` lines in the `hier` report for the
design alone (the ALU is at 100% line/branch/expression).

**Annotated source** (each line marked with its hit count; uncovered lines start with `%`):

    verilator_coverage --annotate annotated design.dat
    less annotated/alu.sv

**HTML report** (line coverage, per file):

    verilator_coverage --write-info coverage.info design.dat
    genhtml coverage.info --output-directory cov_html
    xdg-open cov_html/index.html

---

## 6. Functional coverage (covergroups)

Verilator 5.054 supports covergroups with explicit bins, automatic bins and crosses
(tested). From `tb_top.sv`:

    covergroup alu_cg @(posedge clk iff in_valid);
      cp_op: coverpoint op { bins add = {0}; bins sub = {1}; bins and_op = {2}; bins xor_op = {3}; }
      cp_a:  coverpoint a  { bins zero = {0}; bins max = {255}; bins mid = {[1:254]}; }
      cp_b:  coverpoint b  { bins zero = {0}; bins max = {255}; bins mid = {[1:254]}; }
      x_op_a: cross cp_op, cp_a;
    endgroup
    alu_cg cg = new();
    ...
    $display("functional coverage=%0.1f%%", cg.get_coverage());

Not supported in 5.054: `get_coverage()` on a single coverpoint or cross
(`cg.cp_a.get_coverage()` gives "Unsupported"). Use the covergroup total or the report below.

**Per-bin report** (hit count of every bin):

    verilator_coverage --filter-type covergroup --annotate cg_bins --annotate-points design.dat
    less cg_bins/tb_top.sv

Example:

     000080     cp_op: coverpoint op { bins add = {0}; ... }
    +000080  point: type=covergroup comment= hier=tb_top.alu_cg.cp_op.add
    +000065  point: type=covergroup comment= hier=tb_top.alu_cg.cp_op.sub

Bins with count 0 start with `-`: write a test or constraint to hit them
(coverage closure). The covergroup total also appears in `--report summary` as `covergroup`.

---

## 7. Constrained random stimulus

`randomize()` with constraints works; Verilator uses the `z3` solver (installed by
`install.py`). From `alu_tb_pkg.sv`:

    class alu_txn;
      rand bit [1:0] op;
      rand bit [7:0] a, b;
      constraint c_ops   { op dist {0 := 4, 1 := 3, 2 := 2, 3 := 1}; }
      constraint c_edges { a dist {0 := 1, 255 := 1, [1:254] :/ 8};
                           b dist {0 := 1, 255 := 1, [1:254] :/ 8}; }
    endclass
    ...
    if (t.randomize() == 0) $fatal(1, "randomize failed");

Change the seed with `+verilator+seed+<n>`. The same seed gives the same results.

---

## 8. UVM

The library is the Verilator fork of UVM 2020.3.1 with two patches, installed in
`$UVM_HOME`. The example is in `examples/uvm_project/` (same ALU as above):

| File | Contents |
|---|---|
| `rtl/alu.sv` | design |
| `tb/alu_if.sv` | interface |
| `tb/alu_pkg.sv` | sequence item, smoke and random sequences, driver, monitor, scoreboard (reference model), coverage subscriber (covergroup), agent, env, tests `alu_smoke_test` and `alu_random_test` |
| `tb/tb_top.sv` | clock, reset, DUT, `uvm_config_db` for the interface, `run_test()`, waves on `+WAVES` |

**Compile** (from `examples/uvm_project/sim`; the first time takes about 2-4 minutes
and up to about 3 GB RAM, later builds are faster because ccache reuses the results):

    printf '`verilator_config\ncoverage_off -file "%s/*"\n' "$UVM_HOME" > uvm_cov_off.vlt
    verilator --binary --vpi --assert --coverage --trace -Wno-fatal -Wno-lint -Wno-style -j 1 \
      --timescale 1ns/1ps +incdir+$UVM_HOME +incdir+../tb uvm_cov_off.vlt \
      $UVM_HOME/uvm_pkg.sv ../rtl/alu.sv ../tb/alu_if.sv ../tb/alu_pkg.sv ../tb/tb_top.sv \
      $UVM_HOME/dpi/uvm_dpi.cc --top-module tb_top

- `uvm_cov_off.vlt` switches coverage off for the UVM library, so coverage reports show only your code.
- `--vpi` and `uvm_dpi.cc` are needed by the UVM library.
- `-Wno-lint -Wno-style` hides warnings from inside the UVM library.
- `--timescale 1ns/1ps` gives the UVM library (which has no `` `timescale ``) the same time unit as your files.
- Order: `uvm_pkg.sv` first, then design, interface, your package, top module.

**Run** a test:

    ./obj_dir/Vtb_top +UVM_TESTNAME=alu_smoke_test +UVM_NO_RELNOTES
    ./obj_dir/Vtb_top +UVM_TESTNAME=alu_random_test +UVM_VERBOSITY=UVM_LOW +verilator+seed+3 \
      +verilator+coverage+file+random.dat +WAVES

Expected (end of output):

    UVM_INFO ... uvm_test_top.env.cov [COV] functional coverage=100.0%
    UVM_INFO ... uvm_test_top.env.scb [SCB] checked=200 errors=0
    UVM_INFO ... uvm_test_top [RESULT] TEST PASSED
    UVM_ERROR :    0
    UVM_FATAL :    0

| Plusarg | Meaning |
|---|---|
| `+UVM_TESTNAME=<class>` | which test class to run |
| `+UVM_VERBOSITY=UVM_LOW/MEDIUM/HIGH` | how many `uvm_info` messages to print |
| `+UVM_NO_RELNOTES` | hide the UVM release notes banner |
| `+N=<count>` | number of random items (read by `alu_random_test`) |

Waves (`waves.vcd`), code coverage and covergroup reports work exactly as in sections 3, 5 and 6.
A test passes when `UVM_ERROR : 0`, `UVM_FATAL : 0` and `TEST PASSED` are printed.

Tested in this flow: `uvm_config_db`, factory (`type_id::create`), sequences with
`start_item`/`finish_item`, `randomize()` of sequence items with constraints,
analysis ports, `uvm_subscriber` with a covergroup, objections, `report_phase`.

---

## 9. Synthesis check with Yosys

Checks that the design is synthesizable and shows the cell count:

    yosys -p "read_verilog -sv alu.sv; synth -top alu; stat"

Look for `Number of cells` at the end. Errors here usually mean code that only works in simulation.

---

## 10. Makefile templates for your own project

| Template | For |
|---|---|
| `makefile_templates/sv/Makefile` | SystemVerilog testbench (+ SVA, covergroups) |
| `makefile_templates/uvm/Makefile` | UVM testbench |
| `makefile_templates/Makefile` | smallest flow, tests selected by `+TESTn` (used by `examples/counter`) |

1. Create the folders `rtl/`, `sva/` (optional), `tb/`, `sim/` in your project.
2. Copy the template into `sim/`.
3. Edit the block marked `EDIT HERE` at the top: top module names, folders,
   file order, include folders, defines, test names. Each line has a comment.
4. Run `make help`.

Typical sequence (SV project):

    make check
    make lint
    make regress
    make cov
    make covhtml
    make covopen
    make run TEST=random WAVES=1
    make waves TEST=random

Both templates are used, unchanged, by `examples/sv_project/sim` and
`examples/uvm_project/sim`, so you can try them there first.

Rules the templates expect from your testbench:
- print `TEST PASSED` when the test passes (UVM: in `report_phase`, see `alu_base_test`);
- SV: read the test name from `+TEST=<name>`; UVM: tests are classes selected by `+UVM_TESTNAME`;
- dump waves when `+WAVES` is given, to the file named by `+WAVE_FILE=<name>`.

---

## 11. Differences from VCS / Questa / Verdi

- 2-state simulation: no X or Z values. Reset all registers; `$isunknown` checks do not behave as in a 4-state simulator.
- Assertion pass/fail is not shown in the waveform viewer; failures appear in the log.
- Coverage: the `verilator_coverage` text report combines line, toggle, branch,
  expression, covergroup and cover-property numbers, but there is no UCDB/VDB database
  and no GUI coverage browser. The HTML report (lcov) shows line coverage only.
- `get_coverage()` works only on a whole covergroup (section 6).
- UVM: the Verilator fork of UVM 2020.3.1 with two patches; compile takes minutes, not seconds.
- Full list of supported and unsupported SystemVerilog/UVM constructs, with tested rewrites:
  [SV_UVM_SUPPORT.md](SV_UVM_SUPPORT.md).

---

## 12. Troubleshooting

| Problem | Fix |
|---|---|
| `verilator: command not found` | open a new terminal after `install.py` (it adds PATH to `~/.bashrc`) |
| `%Error: ... Cannot find file containing module` | file missing from the command or wrong file order |
| `%Error-UNSUPPORTED` | the construct is not supported by Verilator 5.054; rewrite it (see section 6 for coverage) |
| simulation stops at the first assertion failure | intended; use `+verilator+error+limit+<n>` to continue |
| coverage numbers look low | remove `verilated_std.sv` from the coverage file (section 5) |
| `xkbcommon: ERROR ... Compose` when starting Surfer | harmless; or start with `LANG=C.UTF-8 surfer waves.vcd` |
| UVM build killed / machine freezes | not enough RAM: close other programs, keep `JOBS=1` |

Report other problems as a GitHub Issue with the full log.
