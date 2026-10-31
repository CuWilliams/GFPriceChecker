#!/usr/bin/env python3
"""Print the timestamp (seconds) of the frame in a Simulator recording where
the scripted take starts: the first frame of the curtain lifting.

Ported unchanged in its logic from TrendFit's
(`../TrendFitApp_App/Tools/Demo/launch_frame.py`), where it was tuned against
the same kind of curtain this app's `DemoCurtainView` puts up.

`simctl io recordVideo` writes a frame only when the screen changes, so a
recording that starts on the static Home screen has one frame at 0 and then
nothing until the app's first frame appears. In a scripted take that frame is
the curtain: flat `systemBackground`, white in light appearance, with nothing
drawn on it (see `DemoCurtainView` for why it has to be flat). That is the
test: the frame is reduced to a 4x4 grid, and every cell must be light *and*
the cells must agree. Icons, dock and wallpaper cannot all be light at once,
and any screen the app draws has cards and text that spread the cells apart.
The curtain holds for `DemoDirector.curtainSeconds` once any seed has landed,
and the frame after that hold is the curtain fading out over the first shot,
which is where every take opens. Reading the pixels beats trusting the
recorder's clock.
"""

import subprocess
import sys

LIGHT = 200          # every channel above this = a white launch frame or curtain
STILL_GAP = 0.8      # seconds with no frame = the curtain holding
GRID = 4             # cells per side the curtain must be light in, all of them
FLAT = 12            # spread across those cells: ~5 with nothing drawn, 18+ once the app draws


def frame_times(path: str) -> list[float]:
    return [float(p.rstrip(",")) for p in subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0",
         "-show_entries", "frame=pts_time", "-of", "csv=p=0", path],
        capture_output=True, text=True, check=True,
    ).stdout.split()]


def mean_pixels(path: str, region: str, cells: int = 1) -> bytes:
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-fps_mode", "passthrough",
         "-vf", f"crop={region},scale={cells}:{cells}",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
        capture_output=True, check=True,
    ).stdout


def launch_index(pts: list[float], pixels: bytes) -> int | None:
    """The curtain is the frame that is light and flat *and then holds*.

    Light alone is not enough. A take recorded straight after the previous one
    opens on that take's last screen, which the terminate then replaces with
    the Home screen, so the recording's own first frame can be light, and a
    detector that stops at the first light frame opens the take on the
    springboard. Pairing light with the still gap that follows it identifies
    the curtain and nothing else.

    Nor is the *first* such frame the answer. The white can hold more than once
    before the curtain lifts (the launch hand-over, then the seed landing behind
    the curtain, then `curtainSeconds`), with frames between the holds that are
    still white and flat. So the scan runs to the end of the white run and
    returns its last hold.

    What bounds that run is flatness, not lightness: a 4x4 average of an app
    screen in light appearance still reads light (white rows on a grey
    grouped background), so `LIGHT` alone never ends it. The curtain is the
    only frame with nothing on it, at a spread of about 5 against 18 or more
    for anything the app draws.
    """
    stride = GRID * GRID * 3
    # The status bar and dynamic island are dark, so the top row is excluded:
    # the curtain is white below them and the Home screen is not.
    skip = GRID * 3
    found = None
    for index in range(min(len(pts), len(pixels) // stride) - 1):
        frame = pixels[index * stride + skip:(index + 1) * stride]
        if min(frame) <= LIGHT or max(frame) - min(frame) > FLAT:
            if found is not None:
                break
            continue
        if pts[index + 1] - pts[index] >= STILL_GAP:
            found = index
    return found


def main(path: str) -> int:
    pts = frame_times(path)
    launch = launch_index(pts, mean_pixels(path, "iw:ih:0:0", GRID))
    if launch is None:
        print("no launch frame found", file=sys.stderr)
        return 1
    # `launch` is the last frame of the held curtain, so the next one is the
    # curtain starting to lift.
    print(pts[launch + 1])
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) != 1:
        print("usage: launch_frame.py <recording.mov>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(args[0]))
