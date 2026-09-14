#!/usr/bin/env python3
"""Turn a real GFPriceChecker backup into a demo dataset that can be published.

    scrub_backup.py --in  ~/GFPCDemoData/backup-raw.json \
                    --out ~/GFPCDemoData/demo-dataset.json

    scrub_backup.py --verify ~/GFPCDemoData/demo-dataset.json

A backup exported from a real device is the dataset we want — real product
names, real differentials, real category spread — and it is also a document
full of personal information. This sits between the two. It reads the JSON
`DataBackupService.exportBackup` writes and emits JSON `importBackup` can read,
with every identifying field replaced.

What it removes, and why each one is not optional:

  * `settings.taxID` is a SIN. `settings.userName` and `settings.accountantEmail`
    name two real people. All three are replaced with fixed placeholders rather
    than emptied, because `importBackup` *skips* empty settings values — an
    empty string would leave whatever the Simulator already held, which is not
    a known state.
  * `receipts[].receiptImageData` is a photograph of a real receipt: store,
    branch, date, card digits, and every unrelated item in the same basket.
    It cannot be scrubbed by editing JSON, because the information is in the
    picture. Each one is replaced with a receipt drawn from the data that
    remains.
  * `receipts[].extractedOCRText` is the text read off that photograph, so it
    carries the same information in plain sight. Regenerated to match the
    drawn receipt.
  * `receipts[].storeName` comes from OCR and usually carries a branch number
    or address. Normalized to the chain name alone.
  * `receipts[].totalAmount` is the total of a real shopping trip, most of
    which is not tracked products. Recomputed as the sum of the GF products
    the receipt verifies, so the drawn receipt adds up to the total the app
    displays.

What it keeps, deliberately: product names, prices, sizes, categories, dates
and the shelf-tag photographs. That is the part worth having. `--strip-notes`
and `--strip-product-images` are there for when a review says otherwise, and
`--dump-product-images` writes them out so that review can actually happen.

The shelf-tag photographs are re-encoded on the way through, downscaled to
`--max-image-dimension` at `--image-quality`. Two reasons, and the second is
the one that matters. A phone camera writes several megapixels per tag and a
backup carries them Base64'd, so a real library runs to well over the 100 MB
a Git host will accept for a single file — the dataset is meant to be
committed. And re-encoding drops every scrap of metadata with it. The
photographs in the library this was built against carried nothing but
dimensions and colour space, because the app's own re-encode had already
stripped the capture metadata; an image that arrived by some other route
would not have been, and EXIF from a phone camera carries GPS.

Orientation is applied to the pixels before the metadata goes, so a tag
photographed sideways stays the way up it was shot.

Nothing here is part of the app target. Working files belong in
`~/GFPCDemoData/`, outside the repo; `.gitignore` covers them anyway in case a
copy lands inside.
"""

import argparse
import base64
import io
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime
from decimal import Decimal, InvalidOperation

from PIL import Image, ImageDraw, ImageFont, ImageOps

# MARK: - Placeholders
#
# Fixed, not random: a demo dataset that seeds a different name on every run is
# a dataset whose screenshots cannot be compared between takes.

PLACEHOLDER_NAME = "Alex Demo"
PLACEHOLDER_EMAIL = "accountant@example.com"

# 000 000 000 is not a valid SIN — the first digit of a real one is never 0 —
# so this cannot collide with a person.
PLACEHOLDER_TAX_ID = "000 000 000"

# RFC 2606 reserves these; an address at one of them can never reach anybody.
RESERVED_EMAIL_DOMAINS = ("example.com", "example.org", "example.net")


# MARK: - Store names
#
# An OCR'd store name reads "LOBLAWS #1052 QUEEN ST W" — the chain is fine to
# publish, the branch says where somebody shops. Match the chain, drop the rest.
# Longest first, so "Real Canadian Superstore" wins over "Superstore".

KNOWN_CHAINS = [
    "Real Canadian Superstore",
    "Shoppers Drug Mart",
    "Save-On-Foods",
    "Whole Foods",
    "Farm Boy",
    "Food Basics",
    "Giant Tiger",
    "No Frills",
    "Bulk Barn",
    "Longo's",
    "Fortinos",
    "FreshCo",
    "Loblaws",
    "Sobeys",
    "Walmart",
    "Costco",
    "Zehrs",
    "Metro",
    "T&T",
]

# What an unrecognized store name becomes. Safety-first: a name this script has
# never seen is a name it cannot vouch for, so it does not survive. The run
# reports every substitution so the map can be extended with --store-map.
UNKNOWN_STORE = "Grocery Store"

# Shelf-tag photographs are re-encoded to this. 1600px on the long edge is
# more than a shelf tag needs to stay readable full-screen at 1080p, and it is
# roughly a twentieth of what the camera wrote.
MAX_IMAGE_DIMENSION = 1600
IMAGE_QUALITY = 75


# MARK: - Receipt rendering
#
# Layout constants mirror `SampleScanImages.ReceiptLayout` in
# GFPriceChecker/Views/CaptureFlow/SampleScanImages.swift. Mirrored, not
# imported — when the drawn receipt changes there, it changes here too.

RECEIPT_WIDTH = 900

# `ReceiptLayout.size` is a fixed 900x1500 because that receipt has a fixed four
# items on it. Here the item count varies, so the height follows the content —
# a two-item receipt really is a short piece of paper. The floor only stops a
# very short one coming out landscape, which reads as a mock-up on sight. 900 is
# a thermal roll's 80mm, so this is a receipt about 100mm long.
RECEIPT_MIN_HEIGHT = 1125
RECEIPT_MARGIN = 70
RECEIPT_BODY = 34
RECEIPT_LINE_HEIGHT = 52
RECEIPT_HEADER = 62
PAPER = (250, 249, 246)
INK = (20, 20, 20)
RULE = (150, 150, 150)

MENLO = "/System/Library/Fonts/Menlo.ttc"
MENLO_REGULAR = 0
MENLO_BOLD = 1


def _font(size, bold=False):
    return ImageFont.truetype(MENLO, size, index=MENLO_BOLD if bold else MENLO_REGULAR)


def _receipt_rows(receipt, products_by_id):
    """The item rows for one receipt: the GF product of every pair it verifies.

    Only the GF product. The regular product's price comes from a shelf tag,
    not from a purchase — it was never on this receipt, and printing it would
    make the demo receipt claim something the app does not.
    """
    rows = []
    for pair_id in receipt.get("productPairIDs", []):
        product = products_by_id.get(pair_id)
        if product is None:
            continue
        price = _decimal(product.get("gfPrice"))
        if price is None:
            continue
        quantity = product.get("quantity") or 1
        name = (product.get("gfProductName") or "ITEM").upper()
        if quantity > 1:
            name = f"{name} X{quantity}"
        rows.append((name, price * quantity))
    return rows


def _receipt_lines(receipt, rows, total):
    """The receipt as lines of text, in draw order.

    This is both what gets drawn and what becomes `extractedOCRText`, so the
    two cannot drift apart.
    """
    when = _parse_iso(receipt.get("purchaseDate"))
    lines = [
        ("header", (receipt.get("storeName") or UNKNOWN_STORE).upper()),
        ("body", when.strftime("%Y-%m-%d %H:%M") if when else ""),
        ("rule", None),
    ]
    lines += [("row", (name, amount)) for name, amount in rows]
    lines += [
        ("rule", None),
        ("total", ("TOTAL", total)),
        ("footer", "THANK YOU FOR SHOPPING"),
    ]
    return lines


def _row_text(name, amount, width_chars):
    """One item row: label and amount separated by a single space.

    The single space is load-bearing and is not a style choice. From
    `SampleScanImages.drawRow`, which measured it: Vision returns a wide
    horizontal gap as a separate text observation, so a two-column receipt OCRs
    as labels and amounts on different lines and `ReceiptParserService` cannot
    pair them. A single space is ordinary word spacing with no gap to split on.
    See issue #51 — when `extractTotal` learns to read a real two-column
    receipt, this can become an honest two-column layout.
    """
    amount_text = f"${amount:.2f}"
    budget = width_chars - len(amount_text) - 1
    if budget > 3 and len(name) > budget:
        name = name[: budget - 1].rstrip() + "…"
    return f"{name} {amount_text}"


def _layout(lines, width_chars):
    """Vertical positions for every line, and the total image height.

    Returned as a list so drawing and measuring cannot disagree, which is what
    lets --verify recompute a receipt's expected height from the JSON alone.
    """
    placed = []
    y = RECEIPT_MARGIN
    for kind, value in lines:
        if kind == "header":
            placed.append((kind, value, y))
            y += RECEIPT_HEADER + 28
        elif kind == "body":
            placed.append((kind, value, y))
            y += RECEIPT_LINE_HEIGHT + 20
        elif kind == "rule":
            placed.append((kind, None, y))
            y += 30
        elif kind in ("row", "total"):
            name, amount = value
            placed.append((kind, _row_text(name, amount, width_chars), y))
            y += RECEIPT_LINE_HEIGHT + (28 if kind == "total" else 0)
        elif kind == "footer":
            y += 20
            placed.append((kind, value, y))
            y += RECEIPT_LINE_HEIGHT
    return placed, max(y + RECEIPT_MARGIN, RECEIPT_MIN_HEIGHT)


def _width_chars():
    """How many body characters fit between the margins. Menlo is monospaced,
    so one measurement answers it for every string."""
    advance = _font(RECEIPT_BODY).getlength("M")
    return int((RECEIPT_WIDTH - 2 * RECEIPT_MARGIN) / advance)


def receipt_text_and_size(receipt, products_by_id):
    """The OCR text and pixel size of the receipt this script would draw.

    Split out from the drawing so --verify can ask for both without rendering.
    """
    rows = _receipt_rows(receipt, products_by_id)
    total = sum((amount for _, amount in rows), Decimal("0"))
    width_chars = _width_chars()
    placed, height = _layout(_receipt_lines(receipt, rows, total), width_chars)
    text = "\n".join(value for kind, value, _ in placed if kind != "rule" and value)
    return text, (RECEIPT_WIDTH, height), total


def draw_receipt(receipt, products_by_id):
    """Renders the substitute receipt as JPEG bytes.

    JPEG at quality 80 because that is what `DataBackupService.loadImageAsBase64`
    writes, so a scrubbed dataset weighs what a real one does.
    """
    rows = _receipt_rows(receipt, products_by_id)
    total = sum((amount for _, amount in rows), Decimal("0"))
    width_chars = _width_chars()
    placed, height = _layout(_receipt_lines(receipt, rows, total), width_chars)

    image = Image.new("RGB", (RECEIPT_WIDTH, height), PAPER)
    draw = ImageDraw.Draw(image)
    left = RECEIPT_MARGIN
    right = RECEIPT_WIDTH - RECEIPT_MARGIN

    for kind, value, y in placed:
        if kind == "rule":
            draw.line([(left, y), (right, y)], fill=RULE, width=2)
        elif kind == "header":
            font = _font(RECEIPT_HEADER, bold=True)
            draw.text(((left + right) / 2, y), value, font=font, fill=INK, anchor="ma")
        elif kind in ("body", "footer"):
            font = _font(RECEIPT_BODY)
            draw.text(((left + right) / 2, y), value, font=font, fill=INK, anchor="ma")
        else:
            font = _font(RECEIPT_BODY, bold=(kind == "total"))
            draw.text((right, y), value, font=font, fill=INK, anchor="ra")

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=80)
    return buffer.getvalue(), total


# MARK: - Leak detection
#
# The backstop. Scrubbing handles the fields we know about; this reads every
# string in the finished file and looks for the shapes personal information
# takes, wherever it ended up — a note the user typed, a product name with a
# phone number in it, an OCR field somebody forgot to regenerate.

LEAK_PATTERNS = [
    ("email address", re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.]+\b")),
    ("SIN-shaped digits", re.compile(r"\b(?!000)\d{3}[ -]?\d{3}[ -]?\d{3}\b")),
    ("card tail", re.compile(r"(?:\*{2,}|x{4,}|#{4,})\s?\d{4}\b", re.I)),
    ("phone number", re.compile(r"\b(?:\+?1[ -.])?\(?\d{3}\)?[ -.]\d{3}[ -.]\d{4}\b")),
    ("postal code", re.compile(r"\b[A-Z]\d[A-Z][ -]?\d[A-Z]\d\b")),
]

# Fields whose value is a Base64 image; scanning megabytes of it for a phone
# number finds only noise.
IMAGE_FIELDS = {"gfImageData", "nonGFImageData", "receiptImageData"}

# Object ids. A UUID whose first nine characters happen to be digits reads as a
# SIN to the pattern above, and about one id in seventy does.
UUID_RE = re.compile(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")


def find_leaks(node, path="$"):
    """Walks the decoded JSON and yields (json path, kind, matched text)."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key in IMAGE_FIELDS:
                continue
            yield from find_leaks(value, f"{path}.{key}")
    elif isinstance(node, list):
        for index, value in enumerate(node):
            yield from find_leaks(value, f"{path}[{index}]")
    elif isinstance(node, str):
        if UUID_RE.fullmatch(node):
            return
        for kind, pattern in LEAK_PATTERNS:
            for match in pattern.finditer(node):
                text = match.group(0)
                if kind == "email address" and text.lower().endswith(RESERVED_EMAIL_DOMAINS):
                    continue
                yield (path, kind, text)


# MARK: - Helpers


def _decimal(value):
    if value is None:
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None


def _parse_iso(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def canonical_store(name, store_map):
    """The chain name alone, or None when nothing is recognized."""
    if not name:
        return None
    haystack = name.strip().lower()
    for raw, canonical in store_map.items():
        if raw.lower() in haystack:
            return canonical
    for chain in KNOWN_CHAINS:
        if chain.lower() in haystack:
            return chain
    return None


def _load(path):
    with open(os.path.expanduser(path), "r", encoding="utf-8") as handle:
        return json.load(handle)


# MARK: - Scrub


def scrub(backup, options, report):
    products_by_id = {p["id"]: p for p in backup.get("productPairs", [])}

    settings = backup.setdefault("settings", {})
    settings["userName"] = options.name
    settings["accountantEmail"] = options.email
    settings["taxID"] = options.tax_id

    # A receipt no product points at has nothing to draw. Its items were all
    # untracked, or the products that cited it were deleted; either way the
    # scrub would redraw it as a blank slip totalling $0.00 and leave it in the
    # library for a take to wander into. Dropped rather than drawn, and nothing
    # can be orphaned by the removal because nothing referenced it.
    if not options.keep_empty_receipts:
        kept = []
        for receipt in backup.get("receipts", []):
            if _receipt_rows(receipt, products_by_id):
                kept.append(receipt)
            else:
                report["receipts_dropped"].append(receipt.get("id", "?"))
        backup["receipts"] = kept

    for receipt in backup.get("receipts", []):
        original = receipt.get("storeName")
        canonical = canonical_store(original, options.store_map)
        if canonical is None:
            canonical = UNKNOWN_STORE
            if original:
                report["unrecognized_stores"][original] += 1
            else:
                # No name to recognize: OCR read nothing off the top of the
                # receipt. Worth its own line, so that a report with nothing in
                # it means nothing happened rather than nothing was reportable.
                report["receipts_without_a_store"] += 1
        receipt["storeName"] = canonical

        rows = _receipt_rows(receipt, products_by_id)
        if not rows:
            report["receipts_without_items"].append(receipt.get("id", "?"))

        image, total = draw_receipt(receipt, products_by_id)
        receipt["receiptImageData"] = base64.b64encode(image).decode("ascii")
        text, _, _ = receipt_text_and_size(receipt, products_by_id)
        receipt["extractedOCRText"] = text
        receipt["totalAmount"] = f"{total:.2f}"
        report["receipts_redrawn"] += 1

    for product in backup.get("productPairs", []):
        if options.strip_notes:
            if product.get("notes"):
                report["notes_stripped"] += 1
            product["notes"] = None
        elif product.get("notes"):
            report["notes_kept"].append((product.get("gfProductName", "?"), product["notes"]))

        for field in ("gfImageData", "nonGFImageData"):
            if not product.get(field):
                continue
            if options.strip_product_images:
                product[field] = None
                product[field.replace("Data", "UUID")] = None
                report["product_images_stripped"] += 1
                continue

            product[field], before, after = recompress(
                product[field], options.max_image_dimension, options.image_quality
            )
            report["product_images_kept"] += 1
            report["image_bytes_before"] += before
            report["image_bytes_after"] += after

    return backup


def recompress(blob, max_dimension, quality):
    """Re-encodes one Base64 JPEG smaller, returning (base64, before, after).

    Applies EXIF orientation to the pixels first and then writes without any
    metadata at all, so the image keeps the way up it was shot and keeps
    nothing else — no camera, no timestamp, no GPS.
    """
    raw = base64.b64decode(blob)
    image = ImageOps.exif_transpose(Image.open(io.BytesIO(raw)))
    if image.mode not in ("RGB", "L"):
        image = image.convert("RGB")
    image.thumbnail((max_dimension, max_dimension), Image.LANCZOS)

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=quality, optimize=True)
    return base64.b64encode(buffer.getvalue()).decode("ascii"), len(raw), buffer.tell()


def dump_product_images(backup, directory):
    """Writes every retained product photograph out as a file.

    These are shelf tags, kept on purpose — but a shelf tag is photographed in
    a shop, and what else is in the frame is a question only a person looking
    at them can answer.
    """
    directory = os.path.expanduser(directory)
    os.makedirs(directory, exist_ok=True)
    written = 0
    for product in backup.get("productPairs", []):
        for field, tag in (("gfImageData", "gf"), ("nonGFImageData", "regular")):
            blob = product.get(field)
            if not blob:
                continue
            name = re.sub(r"[^\w-]+", "_", product.get("gfProductName", "product"))[:40]
            path = os.path.join(directory, f"{name}-{tag}-{product['id'][:8]}.jpg")
            with open(path, "wb") as handle:
                handle.write(base64.b64decode(blob))
            written += 1
    return directory, written


# MARK: - Import schema
#
# Mirrors the Codable structs in DataBackupService.swift. A scrubbed file that
# does not import is worse than one that fails to scrub: the failure is silent
# in places — `Decimal(string:) ?? 0` turns a malformed price into free, and a
# `receiptID` pointing at nothing just leaves the product unverified.
#
# Keys are (name, JSON type, required). Optional Swift properties may be absent
# or null; non-optional ones may be neither.

STRING, NUMBER, BOOL, LIST, OBJECT = str, (int, float), bool, list, dict

BACKUP_SCHEMA = [
    ("version", STRING, True), ("timestamp", STRING, True), ("appVersion", STRING, True),
    ("productPairs", LIST, True), ("receipts", LIST, True), ("settings", OBJECT, True),
]
PRODUCT_SCHEMA = [
    ("id", STRING, True), ("gfProductName", STRING, True), ("gfPrice", STRING, True),
    ("gfSize", STRING, False), ("gfSizeValue", STRING, False), ("gfImageUUID", STRING, False),
    ("gfImageData", STRING, False), ("gfOCRConfidence", NUMBER, True),
    ("nonGFProductName", STRING, True), ("nonGFPrice", STRING, True),
    ("nonGFSize", STRING, False), ("nonGFSizeValue", STRING, False),
    ("nonGFImageUUID", STRING, False), ("nonGFImageData", STRING, False),
    ("nonGFOCRConfidence", NUMBER, True), ("sizeUnit", STRING, False),
    ("quantity", NUMBER, False), ("createdDate", STRING, True), ("category", STRING, False),
    ("notes", STRING, False), ("verified", BOOL, True), ("receiptID", STRING, False),
]
RECEIPT_SCHEMA = [
    ("id", STRING, True), ("purchaseDate", STRING, True), ("storeName", STRING, False),
    ("receiptImageUUID", STRING, False), ("receiptImageData", STRING, False),
    ("totalAmount", STRING, False), ("extractedOCRText", STRING, False),
    ("productPairIDs", LIST, True),
]
SETTINGS_SCHEMA = [
    ("userName", STRING, True), ("accountantEmail", STRING, True), ("taxID", STRING, True),
    ("currencySymbol", STRING, True), ("defaultPaperSize", STRING, True),
    ("defaultDateRange", STRING, True),
]

# JSONDecoder.dateDecodingStrategy = .iso8601 is ISO8601DateFormatter's default
# options, which require a timezone. "2025-04-06T14:32:00" throws; the same
# string with a Z or an offset decodes.
ISO8601_WITH_ZONE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$")


def _check_object(node, schema, where, failures):
    for key, kind, required in schema:
        if key not in node or node[key] is None:
            if required:
                failures.append(f"{where} is missing {key}, which is not optional in Swift")
            continue
        if kind is BOOL:
            if not isinstance(node[key], bool):
                failures.append(f"{where}.{key} is not a boolean")
        elif isinstance(node[key], bool) or not isinstance(node[key], kind):
            failures.append(f"{where}.{key} is {type(node[key]).__name__}, not {kind}")


def _check_date(value, where, failures):
    if value is not None and not ISO8601_WITH_ZONE.match(value):
        failures.append(f"{where} is {value!r}; .iso8601 decoding needs a timezone")


def check_importable(backup):
    """Whether `importBackup` would read this file, without running Swift."""
    failures = []
    if not isinstance(backup, dict):
        return ["the file is not a JSON object"]

    _check_object(backup, BACKUP_SCHEMA, "the backup", failures)
    if backup.get("version") != "1.0":
        failures.append(
            f"version is {backup.get('version')!r}; importBackup throws on anything but \"1.0\""
        )
    _check_date(backup.get("timestamp"), "timestamp", failures)
    _check_object(backup.get("settings") or {}, SETTINGS_SCHEMA, "settings", failures)

    receipt_ids = {r.get("id") for r in backup.get("receipts", [])}
    product_ids = {p.get("id") for p in backup.get("productPairs", [])}

    for index, product in enumerate(backup.get("productPairs", [])):
        where = f"productPairs[{index}]"
        _check_object(product, PRODUCT_SCHEMA, where, failures)
        _check_date(product.get("createdDate"), f"{where}.createdDate", failures)
        for field in ("gfPrice", "nonGFPrice"):
            if _decimal(product.get(field)) is None:
                failures.append(
                    f"{where}.{field} is {product.get(field)!r}; Decimal(string:) fails and "
                    "the import silently stores 0"
                )
        if product.get("receiptID") and product["receiptID"] not in receipt_ids:
            failures.append(f"{where}.receiptID names no receipt; the product imports unverified")

    for index, receipt in enumerate(backup.get("receipts", [])):
        where = f"receipts[{index}]"
        _check_object(receipt, RECEIPT_SCHEMA, where, failures)
        _check_date(receipt.get("purchaseDate"), f"{where}.purchaseDate", failures)
        for pair_id in receipt.get("productPairIDs", []):
            if pair_id not in product_ids:
                failures.append(f"{where}.productPairIDs names a product that is not in the file")

    return failures


# MARK: - Verify


def verify(backup, verbose=True):
    """Re-reads a scrubbed file and answers two questions: is it safe to
    publish, and will `importBackup` read it.

    Checks the output alone, not against the input, so it is worth running on
    a dataset whose provenance has been forgotten. Two honest limits:

      * It cannot tell a real name from a fake one. `settings.userName` is
        printed for a human to look at, not judged.
      * It recognizes a substituted receipt image by its size matching what
        this script would draw for that receipt's items. A real photograph
        will not match; a *different* drawn image of the right size would.
    """
    failures = check_importable(backup)
    warnings = []
    if failures:
        # Every check below indexes into the structure these confirm is there.
        return failures, warnings
    products_by_id = {p["id"]: p for p in backup.get("productPairs", [])}

    settings = backup.get("settings", {})
    tax_id = (settings.get("taxID") or "").strip()
    if tax_id and re.fullmatch(r"(?!0)[\d ]{9,11}", tax_id):
        failures.append(f"settings.taxID looks like a real SIN: {tax_id!r}")
    email = (settings.get("accountantEmail") or "").strip().lower()
    if email and not email.endswith(RESERVED_EMAIL_DOMAINS):
        failures.append(f"settings.accountantEmail is not a reserved domain: {email!r}")
    if not tax_id or not email or not (settings.get("userName") or "").strip():
        failures.append(
            "settings has an empty field; importBackup skips empty values, so the "
            "Simulator would keep whatever it already held"
        )

    for path, kind, text in find_leaks(backup):
        failures.append(f"{kind} at {path}: {text!r}")

    for receipt in backup.get("receipts", []):
        rid = receipt.get("id", "?")
        blob = receipt.get("receiptImageData")
        if not blob:
            warnings.append(f"receipt {rid} has no image")
            continue
        expected_text, expected_size, expected_total = receipt_text_and_size(
            receipt, products_by_id
        )
        try:
            actual_size = Image.open(io.BytesIO(base64.b64decode(blob))).size
        except Exception as error:  # noqa: BLE001 - any decode failure is a fail
            failures.append(f"receipt {rid} image will not decode: {error}")
            continue
        if actual_size != expected_size:
            failures.append(
                f"receipt {rid} image is {actual_size}, not the {expected_size} this "
                "script draws — it may still be the real photograph"
            )
        if (receipt.get("extractedOCRText") or "") != expected_text:
            failures.append(
                f"receipt {rid} extractedOCRText is not the regenerated text — it may "
                "still be read off the real receipt"
            )
        if _decimal(receipt.get("totalAmount")) != expected_total:
            warnings.append(
                f"receipt {rid} totalAmount {receipt.get('totalAmount')} does not match "
                f"its items ({expected_total:.2f})"
            )
        # Not membership of KNOWN_CHAINS — --store-map exists precisely so a
        # chain this script has never heard of can be kept. What a normalized
        # name never has is a branch number or a street address on it.
        store = receipt.get("storeName") or ""
        if re.search(r"[#\d]", store) or len(store) > 28:
            warnings.append(f"receipt {rid} store {store!r} still looks like raw OCR")

    if verbose:
        products = backup.get("productPairs", [])
        dates = sorted(d for d in (_parse_iso(p.get("createdDate")) for p in products) if d)
        categories = Counter(p.get("category") or "uncategorized" for p in products)
        print(f"  {len(products)} products, {len(backup.get('receipts', []))} receipts")
        if dates:
            print(f"  {dates[0]:%Y-%m-%d} to {dates[-1]:%Y-%m-%d}")
        print("  categories: " + ", ".join(f"{k} {v}" for k, v in categories.most_common()))
        if settings.get("userName") != PLACEHOLDER_NAME:
            print(f"  settings.userName is {settings.get('userName')!r} — is that a real person?")

    return failures, warnings


def _report_result(failures, warnings):
    for warning in warnings:
        print(f"  WARN  {warning}")
    for failure in failures:
        print(f"  FAIL  {failure}")
    if failures:
        print(f"\n{len(failures)} problem(s). This file must not be committed or published.")
        return 1
    print("\nClean: no tax ID, no real email, no real receipt photograph.")
    return 0


# MARK: - CLI


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--in", dest="source", help="raw backup exported from the device")
    parser.add_argument("--out", dest="destination", help="scrubbed dataset to write")
    parser.add_argument("--verify", dest="verify_path", help="check an already-scrubbed dataset")
    parser.add_argument("--name", default=PLACEHOLDER_NAME)
    parser.add_argument("--email", default=PLACEHOLDER_EMAIL)
    parser.add_argument("--tax-id", default=PLACEHOLDER_TAX_ID)
    parser.add_argument("--store-map", help="JSON object of {raw name: canonical name}")
    parser.add_argument("--dump-product-images", metavar="DIR",
                        help="write retained shelf-tag photos out for review")
    parser.add_argument("--strip-product-images", action="store_true")
    parser.add_argument("--strip-notes", action="store_true")
    parser.add_argument("--max-image-dimension", type=int, default=MAX_IMAGE_DIMENSION,
                        metavar="PX", help="long edge of a re-encoded shelf-tag photo "
                                           f"(default {MAX_IMAGE_DIMENSION})")
    parser.add_argument("--image-quality", type=int, default=IMAGE_QUALITY,
                        metavar="Q", help=f"JPEG quality for those (default {IMAGE_QUALITY})")
    parser.add_argument("--keep-empty-receipts", action="store_true",
                        help="keep receipts no product verifies, as blank $0.00 slips")
    options = parser.parse_args(argv)

    if options.verify_path:
        print(f"Verifying {options.verify_path}")
        return _report_result(*verify(_load(options.verify_path)))

    if not options.source or not options.destination:
        parser.error("--in and --out are both required (or use --verify)")

    options.store_map = _load(options.store_map) if options.store_map else {}
    report = {
        "receipts_redrawn": 0,
        "unrecognized_stores": Counter(),
        "receipts_without_items": [],
        "receipts_without_a_store": 0,
        "receipts_dropped": [],
        "product_images_kept": 0,
        "product_images_stripped": 0,
        "image_bytes_before": 0,
        "image_bytes_after": 0,
        "notes_kept": [],
        "notes_stripped": 0,
    }

    backup = scrub(_load(options.source), options, report)

    destination = os.path.expanduser(options.destination)
    os.makedirs(os.path.dirname(destination) or ".", exist_ok=True)
    with open(destination, "w", encoding="utf-8") as handle:
        json.dump(backup, handle, indent=2, sort_keys=True)

    print(f"Wrote {destination} ({os.path.getsize(destination) / 1e6:.1f} MB)")
    print(f"  {report['receipts_redrawn']} receipt image(s) and OCR text replaced")
    print(f"  settings.taxID, userName and accountantEmail replaced")
    if report["product_images_kept"]:
        before, after = report["image_bytes_before"], report["image_bytes_after"]
        print(f"  {report['product_images_kept']} shelf-tag photo(s) KEPT — review them")
        print(f"    re-encoded to {options.max_image_dimension}px at q{options.image_quality}, "
              f"metadata dropped: {before / 1e6:.1f} MB -> {after / 1e6:.1f} MB")
    if report["product_images_stripped"]:
        print(f"  {report['product_images_stripped']} product photo(s) stripped")
    if report["notes_stripped"]:
        print(f"  {report['notes_stripped']} note(s) stripped")

    if options.dump_product_images:
        directory, written = dump_product_images(backup, options.dump_product_images)
        print(f"  wrote {written} product photo(s) to {directory} — look at them")

    if report["unrecognized_stores"]:
        print("\nStore names not recognized, replaced with "
              f"{UNKNOWN_STORE!r}. Extend the list with --store-map to keep them:")
        for name, count in report["unrecognized_stores"].most_common():
            print(f"    {count:3d}  {name!r}")

    if report["receipts_without_a_store"]:
        print(f"\n{report['receipts_without_a_store']} receipt(s) carried no store name at "
              f"all — OCR read none — and show as {UNKNOWN_STORE!r}. Nothing to map.")

    if report["receipts_dropped"]:
        print(f"\n{len(report['receipts_dropped'])} receipt(s) dropped — no product verifies "
              "them, so there was nothing to draw. --keep-empty-receipts keeps them as "
              "blank $0.00 slips:")
        for rid in report["receipts_dropped"]:
            print(f"    {rid}")

    if report["receipts_without_items"]:
        print(f"\n{len(report['receipts_without_items'])} receipt(s) verify no products, so "
              "they draw as an empty receipt totalling $0.00:")
        for rid in report["receipts_without_items"]:
            print(f"    {rid}")

    if report["notes_kept"]:
        print(f"\n{len(report['notes_kept'])} note(s) kept verbatim. Read them — they are "
              "free text somebody typed:")
        for name, note in report["notes_kept"]:
            print(f"    {name}: {note!r}")

    print("\nVerifying the result")
    return _report_result(*verify(backup))


if __name__ == "__main__":
    sys.exit(main())
