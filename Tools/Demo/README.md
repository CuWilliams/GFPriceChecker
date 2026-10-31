# Demo tooling

Host-side tooling for the scripted demo pipeline — see
[`docs/SCRIPTED_DEMO_PIPELINE.md`](../../docs/SCRIPTED_DEMO_PIPELINE.md) for the plan this
implements and why it is staged the way it is.

Nothing in this folder is part of the app target. `Tools/` sits outside the synced Xcode
groups, so files here are never compiled into the app.

The raw backup lives in **`~/GFPCDemoData/`**, outside the repo, and `.gitignore` covers
`backup-raw.json` and `GFPCDemoData/` in case a copy lands inside — it is the one file in
this pipeline that must never be committed.

The scrubbed dataset **is** committed, at `Tools/Demo/demo-dataset.json`, and is what
`seed.sh` uses by default. It is the only copy of the demo library not sitting on a single
Mac, and since the raw backup can never join it in the repo, a dataset kept outside would
make the demo library unreproducible the day that Mac died. `--verify` is what licenses it
to be there; run it on anything before committing a replacement.

## Stage 2 — the demo dataset

The dataset is a real backup with the personal information taken out of it. Real data is
worth the trouble: real product names, real differentials, a real spread of categories over a
real year. A fabricated dataset shows the app working on data that cannot argue back, and it
looks it.

### 1. Export a backup from the device

In the app: **Settings → Data Management → Export All Data**, which offers the JSON through the
system share sheet. Save it to the Mac as `~/GFPCDemoData/backup-raw.json`.

This file is personal. It carries a SIN, two real email-adjacent identities, and a photograph
of every receipt scanned — store, branch, date, card digits, and every unrelated item in the
same basket. Keep it out of the repo and off anything shared.

### 2. Scrub it

```bash
python3 Tools/Demo/scrub_backup.py \
    --in  ~/GFPCDemoData/backup-raw.json \
    --out ~/GFPCDemoData/demo-dataset.json \
    --store-map Tools/Demo/stores.json \
    --dump-product-images ~/GFPCDemoData/review/
```

`Tools/Demo/stores.json` is committed, and holds the chain names this library needed that the
built-in list does not carry. Pass it every time: without it those receipts fall back to
`Grocery Store`, so a re-scrub silently loses names an earlier one had.

**Then copy the result over `Tools/Demo/demo-dataset.json` and commit it** — that committed
copy is what `seed.sh` reads. A scrub left in `~/GFPCDemoData/` changes nothing that anyone
else, or any later take, will see. `seed.sh` prints a notice when it spots a newer one there.

Needs Pillow (`pip3 install pillow`); nothing else.

It replaces `taxID`, `userName` and `accountantEmail` with fixed placeholders, normalizes
store names to the chain alone, and replaces every receipt photograph with a receipt **drawn
from the data that survives** — the GF products that receipt verifies, their prices, the
purchase date, the chain name. `extractedOCRText` is regenerated to match the drawing, and
`totalAmount` is recomputed from the items, so the receipt the app displays adds up to the
total it prints.

Placeholders are fixed rather than random on purpose: a dataset that seeds a different name
each run is a dataset whose screenshots cannot be compared between takes.

It **keeps** product names, prices, sizes, categories, dates and the shelf-tag photographs.
That is the part worth having. `--dump-product-images` writes those photographs out as files
so they can actually be looked at before publication — a shelf tag is photographed in a shop,
and what else is in the frame is a question only a person can answer. `--strip-product-images`
and `--strip-notes` are there for when that review says no.

The shelf-tag photographs are re-encoded on the way through — downscaled to
`--max-image-dimension` (1600px on the long edge) at `--image-quality` (75), with EXIF
orientation applied to the pixels and all other metadata dropped. This is not cosmetic. A
phone writes several megapixels per tag and a backup carries them Base64'd, so the library
this was built against came to **170 MB, 168 of it photographs** — past the 100 MB a Git host
will take for one file, and the dataset is meant to be committed. Re-encoded it is 28 MB.
Dropping the metadata is the other half: these particular photographs carried only dimensions
and colour space, because `ImageStorageService` had already re-encoded them, but a picture
that reached the library by some other route would still have its EXIF, and a phone camera
writes GPS into that.

A receipt no product verifies is **dropped**, because there is nothing to draw it from — it
would otherwise land in the demo library as a blank slip totalling $0.00. Nothing can be
orphaned by the removal, since by definition nothing referenced it. `--keep-empty-receipts`
keeps them.

Every run finishes by verifying its own output and exits non-zero if anything failed. Things
it will stop on, in practice:

| Report | What to do |
| --- | --- |
| *Store names not recognized* | Add them with `--store-map stores.json` (`{"raw name": "Chain"}`) or accept `Grocery Store`. |
| *N note(s) kept verbatim* | Read them. Notes are free text somebody typed. `--strip-notes` if any of it is personal. |
| *N shelf-tag photo(s) KEPT* | Look at the dumped files. `--strip-product-images` if a frame has something in it. |
| *N receipt(s) carried no store name* | Nothing to do. OCR read no store off them; they show as `Grocery Store`. |
| *N receipt(s) dropped* | Normal. Nothing verified them, so there was nothing to draw. `--keep-empty-receipts` to keep them. |
| *FAIL phone number at $.productPairs[…].notes* | The leak scan found PII the field scrub does not cover. Fix the source or strip the field. |

### 3. Check a dataset on its own

```bash
python3 Tools/Demo/scrub_backup.py --verify ~/GFPCDemoData/demo-dataset.json
```

Worth running on any dataset whose provenance has been forgotten. It answers two questions
without needing the original:

**Is it safe to publish?** Settings fields are checked against the shapes real ones take (a
SIN's first digit is never 0; a scrubbed address is on an RFC 2606 reserved domain). Then
every string in the file — not just the fields the scrub knows about — is scanned for email
addresses, SIN-shaped digit groups, card tails, phone numbers and postal codes. Receipt images
are recognized as substituted by matching the size this script would draw for that receipt's
items, and `extractedOCRText` by regenerating it and comparing.

**Will `importBackup` read it?** The Codable structs in `DataBackupService.swift` are mirrored
here as a schema, so the check catches a missing non-optional field, a `version` other than
`"1.0"` (which `importBackup` throws on), a date without a timezone (which `.iso8601` refuses),
a price string `Decimal(string:)` cannot parse — that one imports silently as free — and a
`receiptID` pointing at no receipt, which imports the product silently unverified.

Two things it cannot do. It cannot tell a real name from a fake one, so `settings.userName` is
printed for a human to read rather than judged. And it recognizes a substituted receipt by its
size and text, which a real photograph will not match but a *different* drawn image of the
right size would.

### 4. Seed a Simulator

```bash
Tools/Demo/seed.sh                                    # committed dataset, booted Simulator
Tools/Demo/seed.sh ~/GFPCDemoData/demo-dataset.json "iPhone 17 Pro"
```

With no arguments it seeds from the committed `Tools/Demo/demo-dataset.json`, so a fresh
clone needs no setup. Pass a path to seed from a newer scrub instead.

It verifies the dataset first — the same check as §3, because a seed that silently loads an
unscrubbed export is how one ends up in a published video — then builds and installs a DEBUG
build, terminates anything running, and relaunches with `GFPC_DEMO_DATASET` naming the file.

It asks `xcodebuild -showBuildSettings` where the app landed rather than computing the path
from `-derivedDataPath`. Xcode's **Build Location** preference, when set to Custom or to a
shared folder, overrides that flag for the products directory — and the build still succeeds,
so a computed path gives a green build and an install that cannot find the app.

The in-app half is [`GFPriceChecker/Dev/DemoSeed.swift`](../../GFPriceChecker/Dev/DemoSeed.swift),
`#if DEBUG` only: in a release build there is no path that reads a JSON file off disk and
overwrites the user's library. It calls `importBackup(strategy: .replace)`, which wipes the
store and its images before loading, so a take always starts from the dataset rather than
from the dataset plus whatever the last one left behind. It also sets `hasCompletedOnboarding`,
which no backup carries and which would otherwise put an onboarding sheet over the first shot.

Two things worth knowing:

- **Terminate before relaunching.** A running instance keeps the environment it launched
  with, so `simctl launch` over the top silently does nothing new. `seed.sh` does this.
- **Pass an absolute host path.** Simulator processes read host paths directly, so the
  dataset never needs copying into the container — but `~` inside a Simulator process is the
  *app's own container*, not the Mac's home. `seed.sh` expands it on the host; the app takes
  what it is given unchanged.

A bad path, a malformed dataset or a version the importer rejects is a `fatalError`, not a
log line. A take recorded against a store that half-seeded still looks like a take, and the
wrong numbers do not become obvious until somebody watches the finished video.

## Stage 4 — open a named screen

```bash
xcrun simctl terminate booted com.cuwilliams66.GFPriceChecker
SIMCTL_CHILD_GFPC_DEMO_ROUTE=export xcrun simctl launch booted com.cuwilliams66.GFPriceChecker
```

`GFPC_DEMO_ROUTE` opens the app on one screen, after any seeding in the same launch. The
names are `AppRouter.Destination`'s cases:

| Name | Screen |
| --- | --- |
| `capture`, `library`, `reports` | That tab, nothing pushed or presented |
| `captureFlow` | The product capture sheet |
| `manualEntry`, `receiptCapture` | The Library's Add-menu sheets |
| `export`, `settings` | The Reports toolbar sheets |
| `product`, `receipt` | The newest of each, pushed in the Library |

An unknown name, or `product` on an empty store, is a `fatalError` for the same reason a bad
seed is. Terminate first, as with seeding: a running instance keeps its old environment.

The in-app half is [`GFPriceChecker/Dev/DemoRoute.swift`](../../GFPriceChecker/Dev/DemoRoute.swift),
which hands the name to `AppRouter.show(_:)`. Stage 5's director calls `show(_:)` itself;
this hook stays as the quickest way to put a still of one screen in front of a shell.

## Stage 5 — play a scripted take

```bash
Tools/Demo/play.sh tour                 # build, install, seed, play, wait for the end
Tools/Demo/play.sh tour --still         # stop at the script's still() and screenshot it
Tools/Demo/play.sh tour --no-build      # reuse what is installed
```

`GFPC_DEMO_SCRIPT` names a script in
[`GFPriceChecker/Dev/DemoScripts.swift`](../../GFPriceChecker/Dev/DemoScripts.swift), and
[`DemoDirector`](../../GFPriceChecker/Dev/DemoDirector.swift) plays it against `AppRouter`
and the view models: no taps, the same take every run. `tour` visits each tab, a product and
the export sheet, and exists to prove the mechanism; the website's three storyboards are
Stage 6's, below.

`play.sh` seeds from the committed dataset in the same launch unless told `--no-seed` or given
`--dataset`, so every take starts from the same library. Its files go in
`$GFPC_DEMO_HOME/takes/` (default `~/GFPCDemoData/takes/`).

What a launch does, in order: seed, apply any `GFPC_DEMO_ROUTE`, hold the curtain
`curtainSeconds` (1.5 s), lift it, play the script, write the done file.

| Variable | What it does |
| --- | --- |
| `GFPC_DEMO_SCRIPT` | The script to play. An unknown name is a `fatalError`. |
| `GFPC_DEMO_DONE_FILE` | Written when the script ends: `done <script>`, or `failed <script>: <error>`. |
| `GFPC_DEMO_STILL_FILE` | Puts the run in stills mode. `still()` writes it and holds the screen. |
| `GFPC_DEMO_STILL_MARK` | Which `still(_:)` mark to stop at. Unset means `tile`. |

`play.sh` exits non-zero if the script fails, if the app stops running (a bad seed's
`fatalError`, say) or if nothing arrives within three minutes. **A failed script still writes the
done file.** A take that stopped halfway is still a recording, and Stage 6 must not cut and
publish it as one.

### The curtain is flat, on purpose

A scripted launch shows `DemoCurtainView`, plain `systemBackground`, instead of
`LaunchScreenView`. The launch screen's gradient, logo and tagline are light but not flat, and
`launch_frame.py` finds the start of a take by looking for frames with nothing drawn on them.
The flat curtain matches the system launch screen, so the two read as one still hold and the
detector ports with its constants unchanged.

Measured on the first `tour` recording (iPhone 17 Pro, iOS 26.5, light appearance): the system
launch screen and the curtain hold white from 2.96 s to 7.21 s, with a spread of 2–5 across the
4×4 grid against `FLAT = 12`. TrendFit's `launch_frame.py` cut at 8.30 s, on the first frame of
the Capture tab. The seed lands inside that hold, which is why the curtain is held by the
director rather than by a timer. A timer would lift partway through a 28 MB import.

The curtain's 0.6 s fade did not appear in that recording: the frame after the hold is the
finished screen. Either the recorder dropped it (README Tier 0: the recorder loses frames under
load) or it never animated. Either way the cut lands on a fully drawn screen. Look again in
Stage 6 if a take should open on the fade.

The detector depends on light appearance. `record.sh` sets it; a manual recording has to.

### Writing a script

A script is an `async throws` function in `DemoScripts`, listed in `names`. The primitives:

- `push(_:)` calls `AppRouter.show(_:)` and holds `settleSeconds` so the next step runs on a
  screen that has arrived. To go from one sheet to another, `push(.tab(…))` first. `show`
  dismisses and presents in one update, and SwiftUI can drop the presentation.
- `destination(_:)` resolves `DemoRoute`'s names, so `"product"` is the newest product.
- `screen(_:)` waits for a sheet's view model to register through `.demoRegistered(viewModel)`.
  `ProductCaptureFlowView`, `ReceiptCaptureView` and `ExportView` carry the hook.
  `push` forgets earlier registrations, since every one belongs to a sheet `show` just
  dismissed.
- `animate`, `wait`, `waitUntil`, and `still(_:)` / `isCapturing(_:)` for stills.

To drive a capture without a camera, enqueue images on `ScannerImageProvider` before the
scanner opens. The scanner takes them with no UI drawn.

## Stage 6 — record the site's takes and stills

```bash
Tools/Demo/record.sh price-tracking           # build, seed, record, cut, report freezes
Tools/Demo/record.sh receipt-management --no-build
Tools/Demo/record.sh price-tracking --keep    # leave the raw recording beside the take
Tools/Demo/record.sh price-tracking --recut   # cut the kept recording again, no re-record
Tools/Demo/stills.sh all                      # the three site screenshots
```

Takes land in `$GFPC_DEMO_HOME/takes/` and stills in `$GFPC_DEMO_HOME/stills/` (default
`~/GFPCDemoData/`). Both scripts take `--dataset`, `--no-seed`, `--no-build`, `--udid`,
`--appearance` and `--out`, as `play.sh` does. They launch through the same `lib.sh`
`launch_script`, so a take is what `play.sh` plays, with a recorder running around it.

| Script | Site video | Site screenshot (`assets/images/screenshots/`) | Still |
| --- | --- | --- | --- |
| `price-tracking` | `price-tracking.mp4` | `screenshot-08-ProductCaptureFlowView.png` | The finalize screen |
| `receipt-management` | `receipt-management.mp4` | `screenshot-10-ReceiptCaptureView.png` | Matching, the first line selected |
| `reporting-exporting` | `reporting-exporting.mp4` | `screenshot-14-SummaryDashBoardView.png` | The dashboard |

The storyboards are the three scripts in
[`DemoScripts.swift`](../../GFPriceChecker/Dev/DemoScripts.swift). Each one's doc comment
says what the video shows and where its still is. The capture takes scan
`SampleScanImages`' drawn shelf tags and receipt, so real Vision OCR runs on every take, and
each row is tapped by what it reads. A scan that reads differently fails the take; it does not
tap the wrong row.

### How a take is cut

`simctl io recordVideo` writes a frame only when the screen changes, and its file starts when
the recorder starts. `record.sh` notes the wall-clock time at spawn and at stop, and then:

1. **Start.** `launch_frame.py` finds the curtain's white hold and cuts on the frame after
   it, the first drawn screen. It is TrendFit's detector with its constants unchanged (4×4
   grid, top row skipped, `LIGHT = 200`, `FLAT = 12`, `STILL_GAP = 0.8`). `GFPC_DEMO_LEAD_IN`
   moves the cut by that many seconds.
2. **Frame rate.** `-vf fps=60`, **not `-r 60`.** The recording declares 600 fps over its
   sparse frames, and `-r` resampled against that: the receipt take opened on 4 s of white
   that the raw file holds for under one. The filter places each frame by its own timestamp.
   TrendFit's `record.sh` uses `-r 60` and probably has the same fault.
3. **Tail.** The file ends at the last change, so a closing hold on a still screen is not in
   it. `tpad` clones the last frame out to the stop time.
4. **Size.** 1170 wide, H.264 CRF 20, `yuv420p`, `+faststart`, no audio. Stage 7 composites
   these portrait takes into the site's frame.

A script that fails still writes its done file. `record.sh` then stops, keeps the raw
recording to look at, and cuts nothing.

### Checking a take

Every take ends with `freezedetect=n=-55dB:d=0.20`: each stretch of 0.2 s or more with no
change. A scripted `wait` is a freeze too, so the list is read against the storyboard and is
not a pass/fail. A freeze that matches a `wait` is fine. A freeze that matches nothing, or one
longer than its `wait`, is a stall worth chasing. Two were found this way:

- **A tab's first render over the seeded library holds the screen for 2–4 s.** A tab stays
  built once shown, so `prepare` shows the take's tab once behind the curtain (`warm`). The
  receipt sheet counts: it is presented from Library.
- **Pushing onto the Library stack while a sheet is still sliding away stalls the push
  halfway, for seconds.** Hold 1.5 s after a save that dismisses a sheet before pushing.

Measured on iPhone 17 Pro, iOS 26.5: `price-tracking` twice in a row, 31.3 s and 30.0 s, both
with only scripted holds. `receipt-management` 27.5 s and `reporting-exporting` 13.9 s, both
clean.

Still to be dealt with in Stage 7: each scan shows the substitute scanner's sheet as a blank
white sheet for about 2 s.

### Stills

`stills.sh` launches each script in stills mode, waits for its `still()`, screenshots it and
terminates. `--mark NAME` stops at `still("NAME")` instead, and adds `-NAME` to the file name.
The carousel shows each screenshot whole at 1206×2622, so nothing is cropped. Each file is
quantised to 256 colours, at about half the size of the site's current RGB files, and the RMSE
is printed beside it. The three came in at 0.004–0.006. Copy a still over its namesake in the
site repo.
