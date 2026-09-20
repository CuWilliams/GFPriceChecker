# GFPriceChecker — Build 10 (v1.0)

Paste the "What to Test" section below into TestFlight when you upload.

---

## What's New

Nothing you can see. This build is identical to build 9 in the app itself — same screens, same
behaviour, same data.

What changed is two pieces of metadata Apple checks when a build is uploaded:

- The app now declares that it uses no non-exempt encryption, which is simply true — it has no
  networking and no cryptography of any kind. Previously that question was answered by hand on
  every single upload.
- The app now ships a privacy manifest, the file Apple requires to declare which system APIs an
  app touches and why. GFPriceChecker's says what has always been the case: no tracking, no
  data collection, no data leaving the device. The one declared item is that the app remembers
  your own settings on your own device.

---

## What to Test

**No new functionality to test.** This build exists to clear two App Store upload checks, and
nothing about the app changed. If you already tested build 9, a quick confirmation that the app
still launches and your data is intact is all this build needs from you.

### Still outstanding from build 9

If you have not tested build 9 — or you are joining the beta at this build — everything below is
new to you. It arrived in build 9 and has not changed since, so testing it here is exactly as
useful as testing it there.

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
   need real examples of how different shops print it. **This request still stands even if you
   have already tested build 9.**
5. **Open the Export screen** and look at the CSV preview. The header row should be fully visible
   and you should be able to reach the bottom of the preview.
6. **Open Reports with an empty library** — on a fresh install, or before adding anything for a
   given year. It should read "No products for 2026".
7. **If you have an iOS 18 device**, install on it and give the app a general pass. This is
   a new minimum for us and no one has run it on real iOS 18 hardware yet — only the Simulator.

Nothing in this build changes existing data, and backups from build 8 and build 9 import
normally. Pairs you already have keep the quantity they were saved with.
