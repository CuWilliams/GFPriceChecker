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
which hands the name to `AppRouter.show(_:)`. Stage 5's director will call `show(_:)` itself;
this hook is how a still of any screen is reachable from a shell before then.

## Stages 5-7

Not built yet. `record.sh`, `launch_frame.py` and `stills.sh` port from
`../TrendFitApp_App/Tools/Demo/` when the in-app half exists to drive.
