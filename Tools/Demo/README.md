# Demo tooling

Host-side tooling for the scripted demo pipeline — see
[`docs/SCRIPTED_DEMO_PIPELINE.md`](../../docs/SCRIPTED_DEMO_PIPELINE.md) for the plan this
implements and why it is staged the way it is.

Nothing in this folder is part of the app target. `Tools/` sits outside the synced Xcode
groups, so files here are never compiled into the app.

Working files live in **`~/GFPCDemoData/`**, outside the repo. `.gitignore` covers
`backup-raw.json`, `demo-dataset.json` and `GFPCDemoData/` anyway, in case a copy lands
inside — the raw backup is the one file in this pipeline that must never be committed.

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
    --dump-product-images ~/GFPCDemoData/review/
```

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

Every run finishes by verifying its own output and exits non-zero if anything failed. Things
it will stop on, in practice:

| Report | What to do |
| --- | --- |
| *Store names not recognized* | Add them with `--store-map stores.json` (`{"raw name": "Chain"}`) or accept `Grocery Store`. |
| *N note(s) kept verbatim* | Read them. Notes are free text somebody typed. `--strip-notes` if any of it is personal. |
| *N shelf-tag photo(s) KEPT* | Look at the dumped files. `--strip-product-images` if a frame has something in it. |
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

## Stages 3-7

Not built yet. `record.sh`, `launch_frame.py` and `stills.sh` port from
`../TrendFitApp_App/Tools/Demo/` when the in-app half exists to drive.
