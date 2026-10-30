# GFPriceChecker — Build 11 (v1.0)

> **Draft — build 11 has not been cut.** Entries are added as changes merge. Remove this note when
> the build is uploaded.

Paste the "What to Test" section below into TestFlight when you upload.

---

## What's New

### Exports, and a clearer name for the headline figure

- **The size-adjusted figure has a new name.** The number the app leads with — the price
  difference adjusted for package size — used to be labelled "Unit Price Differential". That name
  was misleading: the figure is a dollar amount per package, not a price per gram. It is now
  **Size-Adjusted Differential** everywhere: the product list, the product detail screen, the
  capture screen, the Tax Summary, the Export screen, the PDF and the CSV. The numbers themselves
  have not changed.
- **CSV files open correctly whatever your phone's region.** If your phone's region was set to
  somewhere that writes decimals with a comma — France or Germany, for example — every price in
  the CSV came out as two broken columns. Prices and dates are now always written the way
  spreadsheets expect.
- **CSV unit prices are easier to read.** GF and regular unit prices are now per 100 g for
  products sold by the gram, and per unit (per kg, per mL, per item…) otherwise — the same as the
  product detail screen. A new **Unit Price Basis** column says which. Previously they were per
  single gram, rounded to two places, which made most of them read $0.02.
- **CSV notes with line breaks no longer break the file.** Notes typed or pasted with certain line
  breaks could spill into the next row.
- **PDF amounts are exact.** A few amounts in the PDF's transaction table could be a cent lower
  than the true figure. They now always agree with the totals.

---

## What to Test

1. **Look for the new name.** Open a product pair that has sizes, the Tax Summary, and the Export
   screen. Each should say "Size-Adjusted Differential" where it used to say "Unit Price
   Differential", with the same amounts as before.
2. **Export a CSV and open it** in Numbers, Excel or Google Sheets. Check that every column lines
   up under its heading, that unit prices look sensible (a loaf of bread should be a dollar or two
   per 100 g, not $0.02), and that the Unit Price Basis column is filled in for pairs with sizes.
3. **If you are willing, try a different region.** In Settings → General → Language & Region, set
   the region to France, export a CSV, and open it. Prices should still read `7.99`, not `7,99`,
   and nothing should be split across two columns. Remember to set your region back afterwards.
4. **Export a PDF** and compare a few rows of the transaction table against the totals.

Nothing in this build changes your existing data, and backups from earlier builds import normally.
