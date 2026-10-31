#!/usr/bin/env python3
"""Composite a portrait take into the website's video frame.

    Tools/Demo/composite.py <script>... | all  [--takes DIR] [--out DIR]

Stage 7 of docs/SCRIPTED_DEMO_PIPELINE.md. Takes what record.sh leaves in
--takes (default ~/GFPCDemoData/takes): <script>.mp4, the 1170-wide portrait
take, and <script>.captions.json, the captions the storyboard showed, timed
against that take. Writes to --out (default ~/GFPCDemoData/site):

  <script>.mp4  1920x1080 H.264 at 60 fps with a silent stereo AAC track: the
                spec of the site videos it replaces. The take sits centred at
                full height with rounded corners, on black, and each caption
                is burned in as a blue card in the left-hand panel.
  <script>.vtt  The same captions as WebVTT, for a <track> if the site wants
                one (gfpricechecker.github.io#20).

Both are named as the site serves them; copying them into assets/video/ is
the website's step, not this one.

The site videos carry an audio track because the hand-recorded ones did. It
was silent in all three (-91 dB throughout), so there is no narration to keep:
the captions carry the words, and the track is silent here too.

Exits non-zero if a take or its captions are missing, or if a video comes out
at 50 MB or more, which the site's repo will not take.

Needs ffmpeg built with libfreetype (Homebrew's is). Standard library only.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

SCRIPTS = ["price-tracking", "receipt-management", "reporting-exporting"]
DEMO_HOME = Path(os.environ.get("GFPC_DEMO_HOME", Path.home() / "GFPCDemoData"))

# MARK: - The frame

WIDTH, HEIGHT, FPS = 1920, 1080, 60
# Room above and below the phone, so its rounded corners read as a screen
# rather than as a crop of one.
MARGIN = 20
# iPhone 17 Pro's display corners, scaled from 1206 points-times-3 wide to the
# width the take is drawn at here.
CORNER_FRACTION = 0.135

# The site's --primary-blue, with white text: 8.6:1, past WCAG AA for any size.
CARD_COLOUR = "0x0000FF"
TEXT_COLOUR = "white"
FONT = "/System/Library/Fonts/SFNS.ttf"
FONT_SIZE = 48
LINE_SPACING = 12
CARD_PADDING = 28
# Characters a caption line wraps at. The left panel is about 700 px wide at
# 1080p; this keeps the widest card inside it with room either side.
WRAP = 24
# Each caption fades in and out over this long, card and text together.
CAPTION_FADE = 0.2
VIDEO_FADE_IN, VIDEO_FADE_OUT = 0.3, 0.5

CRF = 22
SIZE_LIMIT = 50 * 1000 * 1000


def reading_seconds(text):
    """DemoDirector.readingSeconds(for:), which the director holds every
    caption but the last to. The last can only be checked here."""
    return max(1.5, 1.0 + 0.3 * len(text.split()))


def probe(path, entries):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", entries, "-of", "json", str(path)],
        check=True, capture_output=True, text=True).stdout
    data = json.loads(out)
    return {**data.get("format", {}), **(data.get("streams") or [{}])[0]}


def filter_path(path):
    """A path as a filter option, refused rather than escaped if it holds any
    character the filtergraph would read as syntax. The only paths here are
    the font and a temporary directory, so in practice that never happens."""
    path = str(path)
    if any(ch in path for ch in ":'\\,;[]="):
        sys.exit(f"Cannot put {path} in a filtergraph")
    return path


def timestamp(seconds):
    whole = int(seconds)
    millis = round((seconds - whole) * 1000)
    if millis == 1000:
        whole, millis = whole + 1, 0
    return f"{whole // 3600:02d}:{whole % 3600 // 60:02d}:{whole % 60:02d}.{millis:03d}"


# MARK: - One video

def composite(script, takes, out, work):
    take = takes / f"{script}.mp4"
    captions_file = takes / f"{script}.captions.json"
    for path in (take, captions_file):
        if not path.exists():
            sys.exit(f"{script}: no {path}. Record it first: Tools/Demo/record.sh {script}")

    info = probe(take, "stream=width,height:format=duration")
    duration = float(info["duration"])
    cues = json.loads(captions_file.read_text())["cues"]

    # Cues are the director's, timed from the curtain lifting, which is the
    # frame record.sh cuts on. Anything past the take's end is dropped.
    cues = [{**c, "start": max(0.0, c["start"]), "end": min(duration, c["end"])}
            for c in cues if c["start"] < duration and c["text"].strip()]
    short = [c for c in cues if c["end"] - c["start"] < reading_seconds(c["text"]) - 0.05]

    phone_h = HEIGHT - 2 * MARGIN
    phone_w = round(int(info["width"]) * phone_h / int(info["height"]) / 2) * 2
    phone_x = (WIDTH - phone_w) // 2
    radius = round(phone_w * CORNER_FRACTION)
    panel = phone_x

    # The mask: black everywhere but a rounded rectangle where the phone sits,
    # drawn over the take. One frame, looped by the overlay. The corner test is
    # antialiased over a pixel.
    x0, x1, y0, y1, r = phone_x, phone_x + phone_w, MARGIN, MARGIN + phone_h, radius
    corner = (f"hypot(max(max({x0 + r}-X,X-{x1 - r - 1}),0),"
              f"max(max({y0 + r}-Y,Y-{y1 - r - 1}),0))")
    inside = f"between(X,{x0},{x1 - 1})*between(Y,{y0},{y1 - 1})"
    mask_alpha = f"255*(1-{inside}*clip({r}+0.5-{corner},0,1))"

    graph = [
        f"color=c=black:s={WIDTH}x{HEIGHT}:r={FPS}:d={duration:.3f}[bg]",
        f"color=c=black:s={WIDTH}x{HEIGHT}:d=1,format=rgba,"
        f"geq=r=0:g=0:b=0:a='{mask_alpha}'[mask]",
        f"[0:v]fps={FPS},scale={phone_w}:{phone_h}:flags=lanczos,setsar=1[phone]",
        f"[bg][phone]overlay=x={phone_x}:y={MARGIN}:shortest=1[framed]",
        f"[framed][mask]overlay=0:0[masked]",
    ]

    last = "masked"
    for i, cue in enumerate(cues):
        text_file = work / f"{script}-{i}.txt"
        text_file.write_text("\n".join(textwrap.wrap(cue["text"], WRAP)))
        a, b = cue["start"], cue["end"]
        alpha = (f"if(lt(t,{a + CAPTION_FADE:.3f}),(t-{a:.3f})/{CAPTION_FADE},"
                 f"if(gt(t,{b - CAPTION_FADE:.3f}),({b:.3f}-t)/{CAPTION_FADE},1))")
        graph.append(
            f"[{last}]drawtext=fontfile={filter_path(FONT)}:textfile={filter_path(text_file)}"
            f":expansion=none:fontsize={FONT_SIZE}:fontcolor={TEXT_COLOUR}"
            f":line_spacing={LINE_SPACING}:text_align=C"
            f":box=1:boxcolor={CARD_COLOUR}:boxborderw={CARD_PADDING}"
            f":x=({panel}-text_w)/2:y=(h-text_h)/2"
            f":enable='between(t,{a:.3f},{b:.3f})':alpha='{alpha}'[c{i}]")
        last = f"c{i}"

    graph.append(
        f"[{last}]fade=t=in:d={VIDEO_FADE_IN},"
        f"fade=t=out:st={max(0.0, duration - VIDEO_FADE_OUT):.3f}:d={VIDEO_FADE_OUT},"
        f"format=yuv420p[v]")

    graph_file = work / f"{script}.filtergraph"
    graph_file.write_text(";\n".join(graph))

    out.mkdir(parents=True, exist_ok=True)
    video = out / f"{script}.mp4"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y",
         "-i", str(take),
         "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000",
         "-/filter_complex", str(graph_file),
         "-map", "[v]", "-map", "1:a",
         "-c:v", "libx264", "-preset", "slow", "-crf", str(CRF),
         "-profile:v", "high", "-pix_fmt", "yuv420p",
         "-c:a", "aac", "-b:a", "32k",
         "-t", f"{duration:.3f}", "-movflags", "+faststart",
         str(video)],
        check=True)

    vtt = out / f"{script}.vtt"
    vtt.write_text("WEBVTT\n\n" + "\n".join(
        f"{i + 1}\n{timestamp(c['start'])} --> {timestamp(c['end'])}\n{c['text']}\n"
        for i, c in enumerate(cues)))

    size = video.stat().st_size
    print(f"{video}  {duration:.1f} s  {size / 1e6:.1f} MB  {len(cues)} captions")
    for c in short:
        print(f"  short caption: {c['end'] - c['start']:.1f} s of {reading_seconds(c['text']):.1f} s "
              f"needed at {c['start']:.1f} s — \"{c['text']}\". Hold longer at the end of the script.")
    if size >= SIZE_LIMIT:
        print(f"  {video.name} is {size / 1e6:.1f} MB; the site's limit is 50 MB. Raise CRF.",
              file=sys.stderr)
        return False
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("scripts", nargs="+", help=f"'all', or any of: {' '.join(SCRIPTS)}")
    parser.add_argument("--takes", type=Path, default=DEMO_HOME / "takes")
    parser.add_argument("--out", type=Path, default=DEMO_HOME / "site")
    args = parser.parse_args()

    scripts = SCRIPTS if args.scripts == ["all"] else args.scripts
    if not Path(FONT).exists():
        sys.exit(f"No font at {FONT}")

    ok = True
    with tempfile.TemporaryDirectory(prefix="gfpc-composite-") as work:
        for script in scripts:
            ok &= composite(script, args.takes.expanduser(), args.out.expanduser(), Path(work))
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
