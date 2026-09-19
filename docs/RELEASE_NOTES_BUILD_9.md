# GFPriceChecker — Build 9 (v1.0)

Paste the "What to Test" section below into TestFlight when you upload.

---

## What's New

**You can now record how many of something you bought.**
Buying three of the same gluten-free product used to mean photographing and scanning it three
times. A product pair now carries a quantity, set from the manual entry form — which is also the
Edit sheet, so pairs you captured by photo can be adjusted afterwards. The library shows an
`x3` badge, and the detail screen shows the extended total alongside the per-item figure.

Per-item numbers still mean what they always did. The price difference for one item, and the
unit prices, do not change with quantity — three loaves cost the same per gram. It's the totals
on the summary screen and in both exports that now reflect what you actually bought, and both
exports gained a Qty column so each line can be reconciled against its unit price.

**Receipt totals now prefill from receipts printed the way real ones are.**
Scanning a receipt was silently failing to pick up the total on most of them. The app was looking
for the word "TOTAL" and a dollar amount together on one line, but receipts print the amount bare
and right-aligned in a second column, which the text recognizer reads as a separate line. If you
have been typing the total in by hand every time, that is why.

**The CSV preview on the Export screen no longer cuts itself off.**
It was capped at a fixed height with no way to scroll down, so the column header row was sliced
in half at the top and the "… and N more rows" line at the bottom was unreachable.

**The Reports tab no longer says "No products for 2,026".**
A stray thousands separator in the year, on the first screen you see if the library is empty.

**The app now runs on iOS 18 and later**, down from iOS 26. If you have an older device or a
spare one that could not install the beta before, it can now. Nothing about the app changes on
iOS 26.

---

## What to Test

1. **Set a quantity.** Add or edit a product pair, set the quantity above 1, and save. Check the
   library badge, then open the pair and confirm the extended total is the per-item difference
   multiplied by the quantity.
2. **Check the totals move with it.** Note the total on the Tax Summary screen, change a pair's
   quantity, and confirm the total changes by the amount you'd expect. Averages are now per item
   purchased rather than per pair, so they will shift too.
3. **Export both formats** with at least one multi-quantity pair in the set. Confirm the CSV and
   the PDF both show a Qty column, and that the line items add up to the grand total at the
   bottom.
4. **Scan a real receipt** — this one matters most, and it is the thing that cannot be tested
   without you. Confirm the total is filled in for you on the review screen. Please try a few
   different shops if you can; the fix was verified against generated receipts, not real paper.
   If a total comes through wrong or blank, the receipt photo and the shop name are the useful
   things to report.

   Also, if any receipt shows a quantity multiplier — lines like "2 @ $3.99", "2 X 3.99", or a
   count on its own line above the item — a photo of that receipt is especially useful to us,
   whether or not anything goes wrong. We are building automatic quantity detection next and
   need real examples of how different shops print it.
5. **Open the Export screen** and look at the CSV preview. The header row should be fully visible
   and you should be able to reach the bottom of the preview.
6. **Open Reports with an empty library** — on a fresh install, or before adding anything for a
   given year. It should read "No products for 2026".
7. **If you have an iOS 18 device**, install on it and give the app a general pass. This is
   a new minimum for us and no one has run it on real iOS 18 hardware yet — only the Simulator.

Nothing in this build changes existing data, and backups from build 8 import normally. Pairs you
already have will show a quantity of 1.
