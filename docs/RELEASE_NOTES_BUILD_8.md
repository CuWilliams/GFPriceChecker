# GFPriceChecker — Build 8 (v1.0)

Paste the "What to Test" section below into TestFlight when you upload.

---

## What's New

**The product scan review screen is now one continuous step.**
Previously, once you picked a name and price the screen jumped on its own to a second
size-entry form. Now name, price, and size are three phases of a single screen with a
"Step 1 of 3" indicator. Your scan results stay visible the whole time — nothing swaps
out from under you — and you tap **Continue** when you're ready. Size is still optional;
there's a **Skip Size** button.

**Deleting a product pair now also deletes its photos.**
Deleted pairs were leaving their photo files behind on the device, quietly using up
storage that nothing ever reclaimed.

**Backups no longer lose unit pricing.**
Exporting a backup and restoring it was silently dropping every product's size and unit
of measure, which reduced restored records to package-price-only and wiped out the Unit
Price Differential. Backups now carry that data through a full round trip. Backup files
from build 7 and earlier still import fine — those records simply have no size data to
restore.

---

## What to Test

1. **Scan a product pair end to end.** Watch the review screen: the scan-results list
   should stay put through all three phases. Confirm it never jumps to a different form
   on its own.
2. **After tapping Continue on the GF product**, the regular-product review should start
   fresh at "Step 1 of 3" with nothing pre-filled.
3. **Try Skip Size** on both products, and separately try **Unit Price** mode with the
   cents/dollars basis. Check the Finalize screen shows the differential you'd expect.
4. **Retake Photo** mid-review — the screen should reset cleanly to step 1 after rescanning.
5. **Delete a product pair** that has photos and confirm the app behaves normally.
6. **Backup round trip:** create a pair with sizes and a unit so Unit Price Differential
   shows, export a backup from Settings, clear all data, then import that backup. The
   restored record must still show its Unit Price Differential. **If you have a backup file
   from build 7, please try importing it too** and confirm it still loads.

Known: size entry is optional throughout — a pair saved without sizes reports package
price differential only, and is excluded from unit-price totals in reports.
