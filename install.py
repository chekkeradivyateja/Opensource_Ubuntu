#!/usr/bin/env python3
"""Install the open-source verification flow on Ubuntu 24.04 LTS (x86-64).

Usage: python3 install.py [--check | --uninstall | --uvm-test]
  (no option)  check, install, self-test
  --check      only check the machine and the packages; changes nothing
  --uvm-test   also compile and run a small UVM test (about 4 min, 3 GB RAM)
  --uninstall  remove the installed tools and the ~/.bashrc block
"""
import argparse, getpass, grp, hashlib, os, platform, shutil, subprocess, sys
import tarfile, tempfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PKG = ROOT / "packages"
LOG = ROOT / "install.log"
DEST = Path("/opt/eda/open_ver_flow")
VERILATOR = DEST / "verilator-5.054"
UVM = DEST / "uvm-2020.3.1-vlt-656f20d-patched"
SURFER = DEST / "surfer-0.7.0"
ICARUS = DEST / "iverilog-13.0"
ARCHIVES = {  # archive -> folder it creates
    "verilator-5.054-ubuntu24.04-x86_64.tar.gz": VERILATOR,
    "uvm-2020.3.1-vlt-656f20d-patched.tar.gz": UVM,
    "surfer_linux_v0.7.0.zip": SURFER,
    "iverilog-13.0-ubuntu24.04-x86_64.tar.gz": ICARUS,
}
APT = ["yosys", "z3", "lcov", "gtkwave", "g++", "make", "perl", "python3",
       "ccache", "zlib1g-dev", "liblz4-dev", "graphviz", "vim-gtk3"]
TOOL_PATH = f"{VERILATOR}/bin:{ICARUS}/bin:{SURFER}"
BASHRC = Path.home() / ".bashrc"
BEGIN, END = "# >>> open_ver_flow >>>", "# <<< open_ver_flow <<<"
ENV = {
    "VERILATOR_ROOT": f"{VERILATOR}/share/verilator",
    "UVM_HOME": f"{UVM}/src",
    "PATH": f"{TOOL_PATH}:" + os.environ.get("PATH", ""),
}
UVM_TB = """import uvm_pkg::*;
`include "uvm_macros.svh"
class smoke_test extends uvm_test;
  `uvm_component_utils(smoke_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    phase.raise_objection(this); #10;
    `uvm_info("SMOKE", "UVM smoke test running", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass
module tb; initial run_test("smoke_test"); endmodule
"""
# Icarus self-test: a 4-bit counter (also drawn by Yosys + Graphviz) and a self-checking testbench
ICARUS_RTL = """module cnt4(input clk, input rst, output reg [3:0] q);
  always @(posedge clk) if (rst) q <= 4'd0; else q <= q + 4'd1;
endmodule
"""
ICARUS_TB = """module cnt4_tb;
  reg clk = 0, rst = 1; wire [3:0] q; integer i, err = 0;
  cnt4 dut(.clk(clk), .rst(rst), .q(q));
  always #5 clk = ~clk;
  initial begin
    $dumpfile("cnt4.vcd"); $dumpvars(0, cnt4_tb);
    @(negedge clk) rst = 0;
    for (i = 1; i <= 20; i = i + 1) begin @(negedge clk); if (q !== i[3:0]) err = err + 1; end
    if (err == 0) $display("PASS: all checks passed"); else $display("FAIL: %0d errors", err);
    $finish;
  end
endmodule
"""


def log(msg=""):
    print(msg, flush=True)
    with open(LOG, "a") as f:
        f.write(msg + "\n")


def ask(question):
    """Ask on the terminal and log the question with the answer. No terminal input (EOF) means "n"."""
    try:
        answer = input(question).strip().lower()
        shown = answer or "(Enter)"
    except EOFError:
        answer, shown = "n", "(no input: n)"
    with open(LOG, "a") as f:
        f.write(f"{question}{shown}\n")
    return answer


def run(cmd, cwd=None, env=None, timeout=None):
    """Run a command, copy its output to the log, return (exit code, output)."""
    try:
        p = subprocess.run(cmd, cwd=cwd, env=env, timeout=timeout, text=True,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        out, code = p.stdout, p.returncode
    except (OSError, subprocess.TimeoutExpired) as e:
        out, code = str(e), 1
    with open(LOG, "a") as f:
        f.write(f"$ {' '.join(map(str, cmd))}\n{out}\n[exit {code}]\n")
    return code, out


# ---------------------------------------------------------------- checks
def os_release():
    return {k: v.strip('"') for k, v in (l.rstrip().split("=", 1) for l in open("/etc/os-release") if "=" in l)}


def ubuntu_version():
    return os_release().get("VERSION", "?")


def check():
    """Print one line per check: status, item, what was found, what is needed, the fix."""
    rows = []  # (status, item, found, required, fix)
    def add(ok, item, found, required, fix, warn=False):
        rows.append(("PASS" if ok else "WARN" if warn else "FAIL", item, found, required, "" if ok else fix))

    osr = os_release()
    add(osr.get("ID") == "ubuntu" and osr.get("VERSION_ID", "").startswith("24.04"),
        "Ubuntu", osr.get("PRETTY_NAME", "?"), "Ubuntu 24.04.x LTS",
        "upgrade to Ubuntu 24.04 LTS (see 'How to fix' below)")
    add(platform.machine() == "x86_64", "CPU", platform.machine(), "x86_64",
        "use a 64-bit Intel/AMD machine or VM")
    add(sys.version_info >= (3, 12), "Python", platform.python_version(), "3.12 or newer",
        "Ubuntu 24.04 comes with Python 3.12; upgrading Ubuntu fixes this")
    ram = int(next(l.split()[1] for l in open("/proc/meminfo") if l.startswith("MemTotal"))) / 2**20
    add(ram >= 7.5, "RAM", f"{ram:.1f} GB", "8 GB recommended, 4 GB minimum",
        "add RAM or give the VM more memory (UVM compile needs about 3 GB)", warn=ram >= 3.5)
    base = next(p for p in [DEST, *DEST.parents] if p.exists())
    free = shutil.disk_usage(base).free / 2**30
    add(free >= 3, "Free disk", f"{free:.1f} GB on {base}", "3 GB", "free disk space on " + str(base))
    add(os.geteuid() != 0, "User", getpass.getuser(), "normal user (not sudo/root)",
        "run 'python3 install.py' without sudo")
    add(bool(shutil.which("sudo")), "sudo", shutil.which("sudo") or "not found",
        "sudo command (your password is checked when installing)",
        "ask your administrator to install sudo and give you sudo rights")
    busy = (run(["pgrep", "-x", "apt|apt-get|dpkg"])[0] == 0
            or run(["pgrep", "-f", "/usr/bin/unattended-upgrade( |$)"])[0] == 0)
    add(not busy, "apt", "busy (updates running)" if busy else "idle", "idle",
        "wait a few minutes for Ubuntu updates to finish, then run again")
    for name, digest in (sums().items() if (PKG / "SHA256SUMS").exists() else [("SHA256SUMS", "")]):
        found = "missing" if not (PKG / name).exists() else "OK" if sha256(PKG / name) == digest else "checksum mismatch"
        add(found == "OK", f"packages/{name}", found, "present, checksum OK", "clone the repository again")

    versions = {a: apt_version(a) for a in APT}
    MISSING_APT[:] = [a for a, v in versions.items() if not v]
    for a, v in versions.items():
        rows.append(("PASS" if v else "TODO", f"apt {a}", v or "not installed", "installed",
                     "" if v else "will be installed (you will be asked)"))
    if MISSING_APT:
        online = internet()
        add(online, "Internet", "reachable" if online else "no connection to archive.ubuntu.com",
            "needed to install missing apt packages", "connect to the internet, or install them manually")
    other = shutil.which("verilator")
    if other and not other.startswith(str(DEST)):
        # run it without our VERILATOR_ROOT, which belongs to the new install, not to this one
        env = {k: v for k, v in os.environ.items() if k != "VERILATOR_ROOT"}
        v = (run([other, "--version"], env=env)[1].strip().splitlines() or ["unknown version"])[0]
        rows.append(("INFO", "Other Verilator", f"{v} at {other}", None,
                     "it is kept; the new 5.054 comes first in PATH in new terminals"))
    other = shutil.which("iverilog")
    if other and not other.startswith(str(DEST)):
        v = (run([other, "-V"])[1].strip().splitlines() or ["unknown version"])[0]
        rows.append(("INFO", "Other Icarus Verilog", f"{v} at {other}", None,
                     "it is kept; the new 13.0 comes first in PATH in new terminals"))

    for st, item, found, req, fix in rows:
        if req is None:
            log(f"{st:5} {item}: found {found}. Note: {fix}")
        else:
            log(f"{st:5} {item}: found {found}; required {req}" + (f". Fix: {fix}" if fix else ""))
    fails = sum(r[0] == "FAIL" for r in rows)
    log("PASS  all checks" if not fails else f"{fails} check(s) failed; nothing was changed.")
    UPGRADE[:] = [1] if rows[0][0] == "FAIL" and osr.get("ID") == "ubuntu" else []
    if UPGRADE:
        log("\nHow to fix: upgrade this machine to Ubuntu 24.04 LTS. The packaged tools need it\n"
            "(glibc 2.38+, Python 3.12); installing only a newer Python does not help.")
        log("Commands:\n  " + "\n  ".join(" ".join(c) for c in upgrade_steps()))
        log("Or install Ubuntu 24.04 LTS fresh: https://ubuntu.com/download/desktop")
    return not fails


MISSING_APT = []
UPGRADE = []  # non-empty when the Ubuntu release must be upgraded
RELEASE_CFG = Path("/etc/update-manager/release-upgrades")


def upgrade_steps():
    """Commands that upgrade Ubuntu to the next LTS release (22.04 -> 24.04)."""
    steps = [["sudo", "apt-get", "update"], ["sudo", "apt-get", "full-upgrade", "-y"]]
    if not shutil.which("do-release-upgrade"):
        steps.append(["sudo", "apt-get", "install", "-y", "update-manager-core"])
    if RELEASE_CFG.exists() and "Prompt=lts" not in RELEASE_CFG.read_text():
        steps.append(["sudo", "sed", "-i", "s/^Prompt=.*/Prompt=lts/", str(RELEASE_CFG)])
    return steps + [["sudo", "do-release-upgrade"]]


def offer_upgrade():
    """Ask the user, then run the upgrade commands one by one (default: No)."""
    log("\nThe installer can run these commands for you now. It takes 30-60 minutes, needs\n"
        "internet and a reboot. BACK UP YOUR FILES FIRST. On a shared/lab machine, ask\n"
        "your administrator before upgrading.")
    answer = ask("Upgrade Ubuntu to 24.04 now? [y/N] ")
    if answer not in ("y", "yes"):
        log("Not upgraded. Run the commands above yourself, reboot, then run install.py again.")
        return
    for cmd in upgrade_steps():
        log("$ " + " ".join(cmd))
        if cmd[-1] == "do-release-upgrade" and Path("/var/run/reboot-required").exists():
            log("A reboot is needed first. Run 'sudo reboot', then run install.py again to continue.")
            return
        code = subprocess.run(cmd).returncode  # interactive: the user answers the upgrade questions
        if code != 0:
            log(f"FAIL  '{' '.join(cmd)}' exited with {code}. Fix the problem shown above, then run install.py again.")
            return
    now = ubuntu_version()
    if now.startswith("24.04"):
        log(f"Upgrade finished (now Ubuntu {now}). Reboot if asked, then run: python3 install.py")
    else:
        log(f"Ubuntu is still {now}: the upgrade did not run. Read the messages from\n"
            "do-release-upgrade above, fix the problem, then run install.py again.")


def apt_version(pkg):
    code, out = run(["dpkg-query", "-W", "-f=${Status} ${Version}", pkg])
    return out.split()[-1] if code == 0 and out.startswith("install ok installed") else ""


def internet():
    import socket
    try:
        socket.create_connection(("archive.ubuntu.com", 80), timeout=5).close()
        return True
    except OSError:
        return False


def sums():
    return {l.split()[1]: l.split()[0] for l in open(PKG / "SHA256SUMS") if l.strip()}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------- install
def install():
    log("== sudo (asks for your password)")
    if subprocess.run(["sudo", "-v"]).returncode != 0:
        sys.exit(f"FAIL  sudo did not work for {getpass.getuser()}. Fix: ask your administrator for sudo rights, "
                 "or check your password.")
    if MISSING_APT:
        cmd = ["sudo", "apt-get", "install", "-y", *MISSING_APT]
        log(f"== {len(MISSING_APT)} apt package(s) missing: {' '.join(MISSING_APT)}")
        answer = ask("Install them now? [Y/n] ")
        if answer not in ("", "y", "yes"):
            sys.exit(f"Stopped. Install them yourself, then run again:\n  sudo apt-get update && {' '.join(cmd)}")
        for c in (["sudo", "apt-get", "update"], cmd):
            if run(c)[0] != 0:
                sys.exit(f"FAIL  {' '.join(c)} failed; see {LOG}")
    user, group = getpass.getuser(), grp.getgrgid(os.getgid()).gr_name
    if run(["sudo", "install", "-d", "-o", user, "-g", group, str(DEST)])[0] != 0:
        sys.exit(f"FAIL  could not create {DEST}; see {LOG}")
    for name, folder in ARCHIVES.items():
        marker, digest = folder / ".installed", sums()[name]
        if marker.exists() and marker.read_text() == digest:
            log(f"==  {folder.name}: already installed")
            continue
        log(f"== unpacking {name}")
        if not safe_rmtree(folder, DEST):  # an old or partial copy of this tool only
            sys.exit(f"FAIL  {folder} is not a normal folder inside {DEST}; nothing was deleted. Check it, then run again.")
        if name.endswith(".zip"):
            with zipfile.ZipFile(PKG / name) as z:
                z.extractall(folder)
            for exe in folder.iterdir():
                exe.chmod(0o755)
        else:
            with tarfile.open(PKG / name) as t:
                t.extractall(DEST, filter="data")
        marker.write_text(digest)
    block = "\n".join([BEGIN, f"export VERILATOR_ROOT={ENV['VERILATOR_ROOT']}",
                       f"export UVM_HOME={ENV['UVM_HOME']}",
                       f"export PATH={TOOL_PATH}:$PATH", END])
    write_bashrc(strip_block(BASHRC.read_text() if BASHRC.exists() else "") + "\n" + block + "\n")
    log(f"== environment written to {BASHRC} (open a new terminal to use it)")


def strip_block(text):
    """Remove our marked blocks: from each END back to the nearest BEGIN before it. Other lines are kept."""
    pos = 0
    while (e := text.find(END, pos)) >= 0:
        b = text.rfind(BEGIN, pos, e)
        if b < 0:  # an END without its BEGIN: leave it, look further
            pos = e + len(END)
            continue
        head = text[:b].rstrip("\n")
        text, pos = head + text[e + len(END):], len(head)
    return text.rstrip("\n") + "\n"


def write_bashrc(text):
    """Keep a copy of the previous ~/.bashrc, then write the new one."""
    if BASHRC.exists():
        backup = BASHRC.with_name(".bashrc.open_ver_flow.bak")
        shutil.copy2(BASHRC, backup)
        log(f"   backup of the previous ~/.bashrc: {backup}")
    BASHRC.write_text(text)


def safe_rmtree(path, inside):
    """Delete a folder only if it is strictly inside 'inside' and not a symlink; otherwise refuse."""
    path, inside = Path(path), Path(inside).resolve()
    if path.is_symlink():
        log(f"REFUSED to delete {path}: it is a link")
        return False
    if not path.exists():
        return True
    real = path.resolve()
    if inside not in real.parents:
        log(f"REFUSED to delete {real}: it is not inside {inside}")
        return False
    shutil.rmtree(real)
    return True


# ---------------------------------------------------------------- self-test
def selftest(uvm):
    env = {**os.environ, **ENV}
    tmp = Path(tempfile.mkdtemp(prefix="open_ver_flow_selftest_"))
    shutil.copytree(ROOT / "examples" / "counter", tmp / "counter")
    sim, rtl = tmp / "counter" / "sim", ["../rtl/counter.sv", "../tb/tb_top.sv"]
    tests = [
        ("Verilator lint", ["make", "lint"], sim, None),
        ("Verilator simulation + assertions", ["make", "regress"], sim, "REGRESSION PASSED"),
        ("Coverage (verilator_coverage + lcov)", ["make", "covhtml"], sim, "lines"),
        ("FST waveform", ["verilator", "--binary", "--trace-fst", "-DDUMP_WAVES", "--Mdir", "obj_fst",
                          "--top-module", "tb_top", *rtl], sim, None),
        ("FST waveform run", ["./obj_fst/Vtb_top", "+TEST1"], sim, "PASS"),
        ("Yosys synthesis", ["yosys", "-p", "read_verilog -sv ../rtl/counter.sv; synth -top counter; stat"],
         sim, "Number of cells"),
    ]
    (tmp / "design").mkdir()
    (tmp / "design" / "cnt4.v").write_text(ICARUS_RTL)
    (tmp / "design" / "cnt4_tb.v").write_text(ICARUS_TB)
    d = tmp / "design"
    tests += [
        ("Icarus Verilog compile", ["iverilog", "-g2012", "-s", "cnt4_tb", "-o", "sim.out", "cnt4.v", "cnt4_tb.v"],
         d, None),
        ("Icarus Verilog simulation + VCD", ["sh", "-c", "vvp -n sim.out && test -s cnt4.vcd"], d,
         "PASS: all checks passed"),
        ("Yosys schematic + Graphviz (SVG)",
         ["sh", "-c", "yosys -q -p 'read_verilog cnt4.v; prep -top cnt4; show -format dot -prefix cnt4 cnt4' "
                      "&& dot -Tsvg cnt4.dot -o cnt4.svg && test -s cnt4.svg"], d, None),
        ("gvim (GTK3 window support)", ["gvim", "--version"], d, "GTK3 GUI"),
    ]
    if uvm:
        (tmp / "uvm").mkdir()
        (tmp / "uvm" / "tb.sv").write_text(UVM_TB)
        u = ENV["UVM_HOME"]
        tests += [
            ("UVM compile", ["verilator", "--binary", "--vpi", "-j", "1", "-Wno-fatal", "-Wno-lint", "-Wno-style",
                             "--top-module", "tb", f"+incdir+{u}", f"{u}/uvm_pkg.sv", "tb.sv",
                             f"{u}/dpi/uvm_dpi.cc"], tmp / "uvm", None),
            ("UVM run", ["./obj_dir/Vtb", "+UVM_TESTNAME=smoke_test"], tmp / "uvm", "UVM_FATAL :    0"),
        ]
    log("== self-test")
    ok = True
    for name, cmd, cwd, expect in tests:
        code, out = run(cmd, cwd=cwd, env=env, timeout=1800)
        good = code == 0 and (expect is None or expect in out)
        ok &= good
        log(f"{'PASS' if good else 'FAIL'}  {name}")
    log("== versions")
    for cmd in (["verilator", "--version"], ["iverilog", "-V"], ["yosys", "-V"], ["dot", "-V"],
                ["z3", "--version"], ["lcov", "--version"], ["gtkwave", "--version"], ["surfer", "--version"],
                ["gvim", "--version"]):
        code, out = run(cmd, env=env)
        line = next((l for l in out.splitlines() if l.strip()), "")
        log(f"{'PASS' if code == 0 else 'FAIL'}  {cmd[0]}: {line.strip()}")
        ok &= code == 0
    if ok:
        safe_rmtree(tmp, tempfile.gettempdir())
    else:
        log(f"Self-test files kept in {tmp}")
    return ok


def uninstall():
    """Remove only the tool folders this installer created (ARCHIVES) and its ~/.bashrc block."""
    for folder in ARCHIVES.values():
        if folder.exists():
            log(f"   removing {folder}" if safe_rmtree(folder, DEST) else f"   kept {folder}")
    if DEST.exists() and not any(DEST.iterdir()):
        DEST.rmdir()  # only if empty
    if BASHRC.exists() and BEGIN in BASHRC.read_text():
        write_bashrc(strip_block(BASHRC.read_text()))
    log("Removed the tool folders above and the ~/.bashrc block. Nothing else was touched; apt packages were kept.")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--check", action="store_true")
    g.add_argument("--uninstall", action="store_true")
    g.add_argument("--uvm-test", action="store_true")
    a = ap.parse_args()
    LOG.write_text("")
    if a.uninstall:
        return uninstall()
    log("== checks")
    if not check():
        if UPGRADE and not a.check:
            offer_upgrade()
        sys.exit(1)
    if a.check:
        return
    install()
    if selftest(a.uvm_test):
        log("ALL PASSED. Open a new terminal, then try: cd examples/counter/sim && make regress")
    else:
        sys.exit(f"Some tests FAILED. Please open an Issue and attach {LOG}")


if __name__ == "__main__":
    main()
