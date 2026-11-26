"""Run real RTL checks and capture sprite_renderer RGB without an FPGA board.

Requires Python + Pillow, and Icarus Verilog (iverilog / vvp) on PATH, or:
    python sim/run.py --iverilog PATH/TO/iverilog --vvp PATH/TO/vvp
Generated ROM data, logs and previews are written to sim/output (gitignored).
"""
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "sim" / "output"


def run_command(args, cwd, env, log):
    result = subprocess.run([str(a) for a in args], cwd=cwd, env=env,
                            capture_output=True, text=True, errors="replace")
    (OUT / log).write_text(result.stdout + result.stderr, encoding="utf-8")
    print(result.stdout.strip(), flush=True)
    if result.stderr:
        print(result.stderr.strip(), file=sys.stderr, flush=True)
    if result.returncode or re.search(r"\b(ERROR|FATAL)\b", result.stdout):
        raise RuntimeError(f"Command failed; see {OUT / log}")


def prepare_roms():
    for name, count, width in (("art", 180480, 12), ("tile", 6144, 12), ("map", 4096, 3)):
        coe = ROOT / f"spore.srcs/sources_1/imports/rom_data/{name}_rom.coe"
        content = coe.read_text(encoding="utf-8")
        radix = int(re.search(r"memory_initialization_radix\s*=\s*(\d+)", content).group(1))
        values = [int(v, radix) for v in re.split(r"[,;\s]+", content.split("memory_initialization_vector=")[1].strip()) if v]
        assert len(values) == count, (name, len(values), count)
        assert all(0 <= v < 2**width for v in values)
        (OUT / f"{name}.mem").write_text("\n".join(f"{v:x}" for v in values) + "\n", encoding="ascii")
    for path in (ROOT / "spore.srcs/sources_1/imports/menu_screens").glob("*.mem"):
        shutil.copy2(path, OUT / path.name)


def make_previews():
    from PIL import Image, ImageDraw, ImageFont

    order = [0, 4, 1, 5, 2, 6, 3, 7]
    labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    keys = ["UP", "UP + RIGHT", "RIGHT", "DOWN + RIGHT", "DOWN", "DOWN + LEFT", "LEFT", "UP + LEFT"]
    tiles = {}
    for path in OUT.glob("render_*.hex"):
        body, variant, frame, direction = map(int, path.stem.split("_")[1:])
        values = path.read_text().split()
        assert len(values) == 80 * 80, (path.name, len(values))
        colors = [int(v, 16) for v in values]
        image = Image.new("RGB", (80, 80))
        image.putdata([(((v >> 8) & 15)*17, ((v >> 4) & 15)*17, (v & 15)*17) for v in colors])
        tiles[body, variant, frame, direction] = image.resize((160, 160), Image.Resampling.NEAREST)
    assert len(tiles) == 144

    font_dir = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts"
    def font(size, bold=False):
        path = font_dir / ("segoeuib.ttf" if bold else "segoeui.ttf")
        return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default(size=size)

    width, margin, pitch = 1392, 24, 168
    def canvas(rows, title, subtitle):
        image = Image.new("RGB", (width, 174 + len(rows)*202 + 44), "#091827")
        draw = ImageDraw.Draw(image)
        draw.text((margin, 18), title, font=font(28, True), fill="#f2f7ff")
        draw.text((margin, 58), subtitle, font=font(16), fill="#a8bdce")
        for c, (label, key) in enumerate(zip(labels, keys)):
            center = margin + c*pitch + 80
            draw.text((center, 94), label, anchor="mt", font=font(25, True), fill="#73e5d1" if len(label)==2 else "#f2f7ff")
            draw.text((center, 128), key, anchor="mt", font=font(12), fill="#a8bdce")
        for r, name in enumerate(rows):
            draw.text((margin, 158+r*202), name, font=font(17, True), fill="#dce9f4")
        draw.text((margin, image.height-33), "RTL simulation | Actual sprite_renderer.v RGB + project ROM assets | Board/timing not verified", font=font(14), fill="#a8bdce")
        return image

    sheet = canvas(["Plant Eater / base", "Plant Eater / all DNA", "Meat Eater / base", "Meat Eater / all DNA"],
                   "Spore Rush - 8-direction player", "Simulated VGA crops. Diagonal headings turn 45 degrees; original body and DNA artwork are retained.")
    for row, (body, variant) in enumerate(((0,0), (0,1), (1,0), (1,1))):
        for col, direction in enumerate(order):
            sheet.paste(tiles[body,variant,0,direction], (margin+col*pitch, 188+row*202))
    sheet.save(OUT / "eight_directions.png")

    frames = []
    for phase in range(8):
        image = canvas(["Plant Eater / all DNA", "Meat Eater / all DNA"],
                       "Spore Rush - 8-direction swim animation", "Eight animation phases captured from the Verilog renderer. Each cell holds one heading.")
        for row, body in enumerate((0,1)):
            for col, direction in enumerate(order):
                image.paste(tiles[body,1,phase,direction], (margin+col*pitch, 188+row*202))
        frames.append(image)
    frames[0].save(OUT / "eight_directions.gif", save_all=True, append_images=frames[1:], duration=100, loop=0, disposal=2)
    print(f"Previews: {OUT / 'eight_directions.png'}\n          {OUT / 'eight_directions.gif'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iverilog")
    parser.add_argument("--vvp")
    parser.add_argument("--preview-only", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.preview_only:
        make_previews()
        return

    portable = ROOT / ".tools/iverilog/iverilog/bin"
    compiler = Path(args.iverilog or shutil.which("iverilog") or portable / "iverilog.exe").resolve()
    runtime = Path(args.vvp or shutil.which("vvp") or portable / "vvp.exe").resolve()
    if not compiler.exists() or not runtime.exists():
        parser.error("Install Icarus Verilog or pass --iverilog and --vvp.")
    env = os.environ.copy()
    env["PATH"] = str(compiler.parent) + os.pathsep + env.get("PATH", "")
    # Relocatable Windows distributions require a relative backslash -B path
    # when the repository path contains spaces. POSIX installations find it themselves.
    base_args = []
    lib = compiler.parent.parent / "lib/ivl"
    if os.name == "nt" and lib.exists():
        base_args = ["-B", str(lib) if " " not in str(lib) else os.path.relpath(lib, OUT)]
    prepare_roms()

    # Compile exactly the Verilog files registered in the Vivado project.
    project = ET.parse(ROOT / "spore.xpr").getroot()
    sources = []
    for fileset in project.findall("./FileSets/FileSet"):
        if fileset.get("Name") == "sources_1":
            for item in fileset.findall("File"):
                path = item.get("Path", "").replace("$PSRCDIR", "spore.srcs")
                if path.endswith(".v"):
                    sources.append(path)
    assert sources and "spore.srcs/sources_1/new/top_game.v" in sources
    for name in ("controls", "renderer"):
        executable = OUT / f"{name}.vvp"
        command = [compiler, *base_args, "-g2012", "-s", f"tb_{name}", "-o", executable,
                   ROOT / "sim/vendor_models.v", ROOT / f"sim/tb_{name}.sv", *[ROOT / s for s in sources]]
        run_command(command, OUT, env, f"{name}_compile.log")
        run_command([runtime, executable], OUT, env, f"{name}_run.log")
    make_previews()
    (OUT / "validation.txt").write_text(
        (OUT / "controls_run.log").read_text() + (OUT / "renderer_run.log").read_text(), encoding="utf-8")


if __name__ == "__main__":
    main()
