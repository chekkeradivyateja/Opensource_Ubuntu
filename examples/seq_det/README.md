# seq_det: Verilog design example

Moore sequence detector for "1011" (overlapping), with a self-checking testbench
(directed pattern + 1000 random bits, reference model, prints `PASS: all checks passed`).

- `rtl/seq_det.v`: design (FSM with 5 states, asynchronous active-low reset)
- `tb/seq_det_tb.v`: testbench, writes `dump.vcd`

Commands for this example (Icarus simulation, waveforms, lint, coverage, synthesis,
schematics, FSM diagram): [docs/COMMANDS.md](../../docs/COMMANDS.md), section 2.
