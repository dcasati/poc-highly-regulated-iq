#!/usr/bin/env python3
"""Encode locally rendered Remotion video, then verify the GitHub GIF."""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parent
TARGET = ROOT.parent / "github-gifs/PrivateNetworkFlow.gif"
MANIFEST = TARGET.with_suffix(".manifest.json")
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true")
args = parser.parse_args()


def source_hash():
    sources = [ROOT.parent / "generate-private-network.py", ROOT.parent / "generate-private-document-review.py",
               ROOT / "package.json", ROOT / "package-lock.json", ROOT / "encode-gif.py"]
    sources += sorted((ROOT / "src").glob("*"))
    h = hashlib.sha256()
    for path in sources:
        h.update(path.name.encode())
        h.update(path.read_bytes())
    return h.hexdigest()


if not args.check:
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    # ffmpeg's palette is generated from the actual local render, not external content.
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-i", str(ROOT / "out/network.mp4"), "-filter_complex",
        "[0:v]split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3",
        "-loop", "0", str(TARGET),
    ], check=True)
    MANIFEST.write_text(json.dumps({
        "source_sha256": source_hash(),
        "gif_sha256": hashlib.sha256(TARGET.read_bytes()).hexdigest(),
    }, indent=2) + "\n")

im = Image.open(TARGET)
assert im.size == (1200, 1374), im.size
assert im.n_frames > 400, im.n_frames
assert im.info.get("loop") == 0, "Must loop infinitely"
durations, distinct = [], set()
for frame in range(im.n_frames):
    im.seek(frame)
    durations.append(im.info.get("duration", 0))
    if frame % 12 == 0:
        distinct.add(hashlib.sha256(im.convert("RGB").tobytes()).hexdigest())
assert all(n > 0 for n in durations)
assert 38000 <= sum(durations) <= 40000, sum(durations)
assert len(distinct) > 30, "Motion/narration must change meaningfully"
assert TARGET.stat().st_size < 12 * 1024 * 1024, "Keep GitHub artifact modest"
manifest = json.loads(MANIFEST.read_text())
assert manifest["source_sha256"] == source_hash(), "Animation sources changed: rebuild GIF"
assert manifest["gif_sha256"] == hashlib.sha256(TARGET.read_bytes()).hexdigest(), "GIF changed"
print(f"Checked {im.n_frames} frames, {sum(durations)/1000:.2f}s, infinite loop, "
      f"{len(distinct)} distinct sampled frames, {TARGET.stat().st_size/1024/1024:.2f} MiB.")
