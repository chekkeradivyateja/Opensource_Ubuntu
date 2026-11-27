#!/usr/bin/env bash
# Maintainer test: Icarus Verilog 13.0 (built by build_iverilog.sh), Graphviz and gvim (apt),
# alone and together with Yosys, before they are added to install.py.
#
# Usage (from the repository folder, as a normal user, in a desktop session so gvim can open):
#   bash packages/scripts/test_new_tools.sh
#
# Installs Graphviz and gvim (vim-gtk3) with apt if missing (asks for your sudo password).
# A gvim window opens for a moment and closes by itself.
# Works only in a new folder under /tmp; prints PASS/FAIL per check and a summary.
# Writes the full output to /tmp/new_tools_test_<time>.txt (send that file back).
set -uo pipefail

VER=13.0
PREFIX=/opt/eda/open_ver_flow/iverilog-$VER
REPO=$(cd "$(dirname "$0")/../.." && pwd)
PKG=$REPO/packages/iverilog-$VER-ubuntu24.04-x86_64.tar.gz
STAMP=$(date +%Y%m%d_%H%M%S)
REPORT=/tmp/new_tools_test_$STAMP.txt
exec > >(tee "$REPORT") 2>&1

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "PASS  $*"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL  $*"; }
info() { echo "INFO  $*"; }
# check NAME EXPECT_TEXT CMD...   (exit code 0 and, if EXPECT_TEXT is not empty, text in the output)
check() {
  local name=$1 expect=$2; shift 2
  local out code
  out=$("$@" 2>&1); code=$?
  printf '%s\n' "$out" > "$W/$(echo "$name" | tr -c 'A-Za-z0-9' _).out"
  if [ $code -eq 0 ] && { [ -z "$expect" ] || grep -q -- "$expect" <<<"$out"; }; then ok "$name"
  else bad "$name (exit $code)"; printf '%s\n' "$out" | tail -n 8 | sed 's/^/      /'; fi
}

. /etc/os-release
echo "== $(date)  $PRETTY_NAME  $(uname -m)  $(nproc) cores  $(free -g | awk '/Mem:/{print $2}') GB RAM"

# ---------------------------------------------------------------- apt packages
echo; echo "== apt packages"
missing=()
for p in graphviz vim-gtk3; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "Not installed: ${missing[*]}; installing with apt."
  sudo apt-get update && sudo apt-get install -y "${missing[@]}"
fi
for p in graphviz vim-gtk3; do info "apt package $p $(dpkg-query -W -f='${Version}' "$p" 2>/dev/null)"; done

W=$(mktemp -d /tmp/new_tools_test_XXXXXX)
cd "$W"

# ---------------------------------------------------------------- gvim
echo; echo "== gvim (apt vim-gtk3)"
check "gvim is installed" "" command -v gvim
check "gvim version 9.x with GTK3 GUI" "+gui_gtk3" sh -c 'gvim --version | head -n 1 && gvim --version | grep -o "+gui_gtk3"'
cat > ed.v <<'EOF'
module m(input a, output b);
  assign b = a;
endmodule
EOF
cat > ed.sv <<'EOF'
module s; logic [3:0] x; initial begin x = 4'hA; $display("%h", x); end endmodule
EOF
# file type + syntax colours with filetype/syntax switched on (the GUI test below checks Ubuntu's defaults)
for f in ed.v ed.sv; do
  rm -f ft.txt
  vim -Nes -c 'filetype plugin indent on' -c 'syntax on' -c "e $f" \
      -c "call writefile([&ft . ' ' . exists('b:current_syntax')], 'ft.txt')" -c 'qa!' >/dev/null 2>&1
  want=$([ $f = ed.v ] && echo "verilog 1" || echo "systemverilog 1")
  got=$(cat ft.txt 2>/dev/null)
  [ "$got" = "$want" ] && ok "$f opens as ${want% 1} with colours" || bad "$f file type/colours: got '$got' (expected '$want')"
done
# edit and save without the GUI (same editing engine as gvim)
check "edit + save a file (vim -es)" "" sh -c "vim -Nes -c '1normal! O// edited by test' -c 'wq' ed.v && head -n 1 ed.v | grep -q 'edited by test'"
# open the real gvim window with the user's normal settings, let it write a file from inside the GUI, then close
if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  rm -f gvim_ok.txt
  timeout 30 gvim -f -c "call writefile(['gui ' . has('gui_running') . ' ft ' . &ft . ' syn ' . exists('b:current_syntax')], 'gvim_ok.txt')" -c 'qa!' ed.sv >/dev/null 2>&1
  got=$(cat gvim_ok.txt 2>/dev/null)
  [ "$got" = "gui 1 ft systemverilog syn 1" ] && ok "gvim window opened and closed (GUI running, .sv in colour by default)" \
    || bad "gvim window test: got '$got' (expected 'gui 1 ft systemverilog syn 1')"
else
  info "no desktop session (DISPLAY/WAYLAND_DISPLAY empty): gvim window not tested; run this script in a desktop terminal"
fi

check "dot -V reports 2.43.0" "2.43.0" dot -V
cat > g.dot <<'EOF'
digraph t { rankdir=LR; a [shape=circle]; b [shape=doublecircle]; a -> b [label="1"]; b -> a [label="0"]; }
EOF
check "dot renders SVG" "" dot -Tsvg g.dot -o g.svg
check "dot renders PNG" "" dot -Tpng -Gdpi=80 g.dot -o g.png
check "dot renders PDF" "" dot -Tpdf g.dot -o g.pdf
check "SVG/PNG/PDF files are not empty" "" test -s g.svg -a -s g.png -a -s g.pdf

# ---------------------------------------------------------------- Icarus 13.0
echo; echo "== Icarus Verilog $VER in $PREFIX"
if [ ! -x "$PREFIX/bin/iverilog" ]; then
  bad "Icarus not found at $PREFIX/bin/iverilog. Run: bash packages/scripts/build_iverilog.sh"
else
  apt_iv=$(dpkg-query -W -f='${Status} ${Version}' iverilog 2>/dev/null | grep 'install ok installed' | awk '{print $NF}')
  [ -n "$apt_iv" ] && info "apt iverilog $apt_iv is also installed; our PATH puts $VER first" \
                   || info "no apt iverilog installed (good: no second version)"
  export PATH=$PREFIX/bin:$PATH
  check "iverilog -V reports $VER" "Icarus Verilog version $VER" iverilog -V
  check "vvp -V reports $VER" "$VER" vvp -V
  check "iverilog is our build" "$PREFIX/bin/iverilog" command -v iverilog

  # Design flow example: Moore "1011" sequence detector with a self-checking testbench
  mkdir rtl tb
  cat > rtl/seq_det.v <<'EOF'
module seq_det (input wire clk, input wire rst_n, input wire din, output reg dout);
  localparam [2:0] S0 = 3'd0, S1 = 3'd1, S10 = 3'd2, S101 = 3'd3, S1011 = 3'd4;
  reg [2:0] state, next;
  always @(posedge clk or negedge rst_n)
    if (!rst_n) state <= S0; else state <= next;
  always @(*) begin
    case (state)
      S0:    next = din ? S1    : S0;
      S1:    next = din ? S1    : S10;
      S10:   next = din ? S101  : S0;
      S101:  next = din ? S1011 : S10;
      S1011: next = din ? S1    : S10;
      default: next = state;
    endcase
  end
  always @(*) dout = (state == S1011);
endmodule
EOF
  cat > tb/seq_det_tb.v <<'EOF'
`timescale 1ns/1ps
module seq_det_tb;
  reg clk = 0, rst_n = 0, din = 0;
  wire dout;
  integer errors = 0, checks = 0, i;
  reg [3:0] hist; reg exp;
  reg [15:0] pattern = 16'b1011_0110_1101_1011;
  seq_det dut (.clk(clk), .rst_n(rst_n), .din(din), .dout(dout));
  always #5 clk = ~clk;
  always @(posedge clk or negedge rst_n) if (!rst_n) hist <= 4'b0000; else hist <= {hist[2:0], din};
  always @(negedge clk) if (rst_n) begin
    checks = checks + 1; exp = (hist == 4'b1011);
    if (dout !== exp) errors = errors + 1;
  end
  initial begin
    $dumpfile("dump.vcd"); $dumpvars(0, seq_det_tb);
    #12 rst_n = 1;
    for (i = 15; i >= 0; i = i - 1) @(negedge clk) din = pattern[i];
    for (i = 0; i < 1000; i = i + 1) @(negedge clk) din = $random;
    @(negedge clk);
    $display("checks=%0d errors=%0d", checks, errors);
    if (errors == 0 && checks > 0) $display("PASS: all checks passed"); else $display("FAIL: %0d errors", errors);
    $finish;
  end
endmodule
EOF
  # same command line as the design Makefile of the Windows flow
  check "Verilog compile (-g2012, -y library search)" "" iverilog -g2012 -s seq_det_tb -y rtl -y tb -Y .v -o sim.out tb/seq_det_tb.v
  check "Verilog simulation: self-check PASS" "PASS: all checks passed" vvp -n sim.out
  check "VCD waveform written" "" test -s dump.vcd
  sed 's/dump\.vcd/dump_fst.fst/' tb/seq_det_tb.v > tb_fst.v
  check "FST waveform (vvp -fst)" "" sh -c 'iverilog -g2012 -s seq_det_tb -o fst.out rtl/seq_det.v tb_fst.v && vvp -n fst.out -fst >/dev/null && test -s dump_fst.fst && ! grep -q enddefinitions dump_fst.fst'
  # 4-state values (X/Z) - Verilator cannot show these, Icarus can
  cat > xz.v <<'EOF'
module xz; reg [3:0] a; wire [3:0] b = 4'bz01x;
  initial begin #1 $display("a=%b b=%b", a, b); $finish; end
endmodule
EOF
  check "4-state X/Z values" "a=xxxx b=z01x" sh -c 'iverilog -o xz.out xz.v && vvp -n xz.out'
  # a wrong design must be caught
  sed 's/S101:  next = din ? S1011 : S10;/S101:  next = din ? S1011 : S0;/' rtl/seq_det.v > rtl_bug.v
  check "bug injected: simulation reports FAIL" "FAIL:" sh -c 'iverilog -g2012 -s seq_det_tb -o bug.out rtl_bug.v tb/seq_det_tb.v && vvp -n bug.out'
  printf 'module broken(; endmodule\n' > broken.v
  if iverilog -o broken.out broken.v >broken.txt 2>&1; then bad "syntax error is reported"; else ok "syntax error is reported (non-zero exit)"; fi

  # SystemVerilog subset used in the course (-g2012)
  cat > sv.sv <<'EOF'
module sv_tb;
  typedef enum logic [1:0] {IDLE, RUN, DONE} st_t;
  typedef struct packed { logic [3:0] hi; logic [3:0] lo; } byte_t;
  st_t st; byte_t b; logic [7:0] q[$]; int arr[4]; int sum;
  function automatic int add(input int x, input int y); return x + y; endfunction
  always_comb sum = add(arr[0], arr[1]);
  initial begin
    st = RUN; b = 8'hA5; arr = '{1, 2, 3, 4}; q.push_back(8'h11); q.push_back(8'h22);
    #1;
    assert (sum == 3) else $error("sum wrong");
    $display("st=%s hi=%h lo=%h sum=%0d qsize=%0d", st.name(), b.hi, b.lo, sum, q.size());
    foreach (arr[i]) if (arr[i] != i + 1) $error("arr wrong");
    $finish;
  end
endmodule
EOF
  check "SystemVerilog subset (enum, struct, queue, function, assert)" "st=RUN hi=a lo=5 sum=3 qsize=2" sh -c 'iverilog -g2012 -o sv.out sv.sv && vvp -n sv.out'
  # the repository's own SV example (Verilator flow) - informational only
  if out=$(iverilog -g2012 -o repo_counter.out "$REPO/examples/counter/rtl/counter.sv" "$REPO/examples/counter/tb/tb_top.sv" 2>&1); then
    info "examples/counter also compiles with Icarus"
  else
    info "examples/counter does not compile with Icarus (expected for some SV/SVA; Verilator is the SV tool):"
    printf '%s\n' "$out" | head -n 3 | sed 's/^/      /'
  fi

  # ---------------------------------------------------------------- Yosys + Graphviz (design flow pictures)
  echo; echo "== Yosys $(yosys -V 2>&1 | head -n 1 | awk '{print $2}') + Graphviz"
  RD="read_verilog rtl/seq_det.v"
  check "RTL schematic (yosys prep + show -> dot -> SVG)" "" sh -c "yosys -q -p '$RD; prep -top seq_det; show -format dot -prefix seq_det_rtl seq_det' && dot -Tsvg seq_det_rtl.dot -o seq_det_rtl.svg && test -s seq_det_rtl.svg"
  check "Gate schematic (yosys synth + show -> SVG)" "" sh -c "yosys -q -p '$RD; synth -top seq_det; show -format dot -prefix seq_det_synth seq_det' && dot -Tsvg seq_det_synth.dot -o seq_det_synth.svg && test -s seq_det_synth.svg"
  check "Synthesis statistics" "Number of cells" yosys -p "$RD; synth -top seq_det; stat"
  check "FSM extraction (kiss2)" "" sh -c "yosys -q -l fsm_report.txt -p '$RD; proc; opt_expr; opt_clean; fsm_detect; fsm_extract; fsm_opt; fsm_info; fsm_export -origenc -o seq_det.kiss2' && test -s seq_det.kiss2"
  if [ -s seq_det.kiss2 ]; then
    n=$(grep -c '^[01-]' seq_det.kiss2)
    { echo "digraph fsm {"; echo "  rankdir=LR;";
      awk '/^\./{next} NF==4{print "  \"" $2 "\" -> \"" $3 "\" [label=\"" $1 "\"];"}' seq_det.kiss2; echo "}"; } > seq_det_fsm.dot
    check "FSM diagram drawn (dot -> SVG)" "" dot -Tsvg seq_det_fsm.dot -o seq_det_fsm.svg
    [ "$n" = 10 ] && ok "FSM has 10 transitions (as on Windows)" || bad "FSM has $n transitions (Windows flow found 10)"
  fi
  check "Yosys hierarchy check of the design" "" yosys -q -p "read_verilog -DTEST rtl/seq_det.v; hierarchy -check -top seq_det"
fi

# ---------------------------------------------------------------- the package file
echo; echo "== package $PKG"
if [ -f "$PKG" ]; then
  info "size $(stat -c %s "$PKG") bytes, SHA-256 $(sha256sum "$PKG" | cut -d' ' -f1)"
  # unpack exactly like install.py does (tarfile, filter="data") into a scratch folder
  check "package unpacks with install.py's method" "" python3 -c "import tarfile,sys; tarfile.open(sys.argv[1]).extractall(sys.argv[2], filter='data')" "$PKG" "$W/unpack"
  check "package has iverilog-$VER/bin/iverilog and vvp" "" test -x "$W/unpack/iverilog-$VER/bin/iverilog" -a -x "$W/unpack/iverilog-$VER/bin/vvp"
  info "package size unpacked: $(du -sh "$W/unpack" | cut -f1)"
else
  bad "package not found: $PKG (run build_iverilog.sh)"
fi

echo
echo "== SUMMARY: $PASS passed, $FAIL failed"
echo "Pictures to look at: $W/seq_det_rtl.svg $W/seq_det_synth.svg $W/seq_det_fsm.svg"
echo "   open them with:  xdg-open $W/seq_det_fsm.svg"
echo "Waveform to look at: gtkwave $W/dump.vcd   or   surfer $W/dump.vcd"
echo "Full output: $REPORT"
[ $FAIL -eq 0 ]
