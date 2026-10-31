# GFPriceChecker — cross-platform test vectors

Plain inputs and expected outputs for the behaviour [PRODUCT_DEFINITION.md](../PRODUCT_DEFINITION.md)
says must match. **They are normative:** an implementation of the product, on any platform, must
pass every vector here. When a vector and a platform disagree, the platform has the bug, or the
vector changes here first, in a reviewed PR, and every platform follows.

| File | Covers |
|---|---|
| `pricing.json` | §3 differentials and the worked example, package size from a unit price, size and unit-price text parsing, §4 size units |
| `reporting.json` | Totals, year and date-range filters, export presets, custom ranges, by-category and by-month groups, the demo dataset's figures |
| `csv.json` | §6: the column headers and whole CSV files, character for character |
| `receipt-parsing.json` | Store name, date, line items and total from receipt text; matching tracked products to line items |
| `price-ranking.json` | Shelf-tag price candidates and their ranking, product name, reading order of recognised text |
| `validation.json` | Input limits and every validation rule |
| `backup/backup.json` | §7: what reading each other file in `backup/` gives, and decimal strings |

Every case has an `input` and an `expected`; most have a `name` to report on failure, and some a
`note` saying why the case exists.

## Conventions

**Decimals are strings**, never JSON numbers, so no parser turns them into floating point.

**An expected decimal matches by its own precision.** Round the actual value half-up to as
many decimal places as the expected string has, then compare by value: `"5.6255555556"` is the
worked example cut at 10 places, and `"5.63"` is the same figure as displayed. A value that
terminates is written in full. Trailing zeros do not matter beyond setting the places: `"4.00"`
matches 4.

**Rounding is half-up**, away from zero, wherever the product rounds — display, CSV and these
comparisons. Several vectors sit exactly on a half cent to pin this: 0.465 is 0.47, and 3.845 is
3.85.

**Floats are JSON numbers** — OCR confidences, box coordinates, ranking scores — and match within
±0.0001. The product computes them in 32-bit floats.

**Instants are ISO 8601 in UTC**, `2026-03-14T17:00:00Z`, with whole seconds. Time zones are IANA
identifiers (`America/Toronto`), and a case that depends on one names it. A receipt's date, which
has no time zone, is a local calendar day: `"2024-12-27"`.

**Absent is `null` or a missing key**, and means the value does not exist — never zero. Where an
input field is missing, its default is: `quantity` 1, `verified` false, product names empty.

**Enumerations are written as the product names them:** size units by their label (`"g"`,
`"fl oz"`), export presets by theirs (`"Current Year"`), and qualities, regions and bases by
name (`"high"`, `"top"`, `"cents"`).

**Report rows** in `reporting.json` and `csv.json` carry the pair's figures plus a
`reportingDate`, which is already resolved: the receipt's purchase date when there is one,
otherwise the created date (§1).

**CSV text** is the file's content without its UTF-8 byte-order mark, lines joined by `\n`, with
no line break after the last row. With no rows it is the header line and one `\n`. Rows are
oldest first; rows with the same date keep their input order.

**Decimal text** — a price or size the user typed, and every decimal string in a backup — is
read only in the plain format [PRODUCT_DEFINITION.md](../PRODUCT_DEFINITION.md) §2 sets out.
`validation.json` and `backup/backup.json` pin it with inputs a lenient parser half-reads:
`"12.99abc"`, `"1,5"`, `"1e3"`, a fullwidth digit.

**Validation results** are `{"ok": value}`, carrying the trimmed or parsed value, or
`{"error": "<case>"}` with that case's `field`, `max` or `value`. A product pair is
`{"valid": true}` or its first error, in field order.

**Coordinates** in `price-ranking.json` are normalised 0–1 with the origin at the bottom left,
as iOS's Vision reports them. A platform whose OCR uses a top-left origin flips `y` before
applying these rules.

## What is deliberately not here

Behaviour the iOS app has but nobody would choose is left out, so it does not become a rule:
expanding abbreviations inside words (`Snacks` read as `snacookies`), reading `COFFEE` as a
discount line because it contains `off`, and pairing prices off by one on product-first receipts
with several items.

## Changing a vector

1. Change it here, in a PR, and say in the PR which platform behaviour it changes.
2. In GFPriceChecker, run `scripts/sync-vectors.sh` to update the vendored copy at
   `Packages/GFCore/Tests/GFCoreTests/Vectors/`, and fix GFCore until `VectorTests` passes.
   `scripts/sync-vectors.sh --check` fails, and so does a push, while the two copies differ.

## Where the data came from

The `backup/` files are hand-written, except `demo.json` and `empty.json`, which are
GFPriceChecker's `Tools/Demo` datasets. `demo.json` has its images removed. Its receipt text was
regenerated from the records when the dataset was scrubbed. Every name, email and tax ID in these
files is a placeholder: never commit a real receipt image or anyone's personal details here.

Expected values for pricing, reporting and CSV were computed independently of the iOS code, in
arbitrary-precision decimal arithmetic, and then checked against the iOS implementation.
