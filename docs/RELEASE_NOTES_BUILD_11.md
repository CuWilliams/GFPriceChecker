# GFPriceChecker — Build 11 (v1.0)

> **Draft — build 11 has not been cut.** Entries are added as changes merge. Remove this note when
> the build is uploaded.

Paste the "What to Test" section below into TestFlight when you upload.

---

## What's New

### Receipts add up, and missing sizes are no longer counted as zero

- **Receipt totals count quantity.** If you bought three of something, a receipt's Package Price
  Differential Total counted it once. It now counts all three, and each product row on the
  receipt shows the amount for the whole purchase, so the rows add up to the total.
- **Receipt amounts are formatted as currency**, rather than as raw numbers with a dollar sign in
  front.
- **No size data now reads "—", not $0.00.** When none of the products in a period have package
  sizes, the size-adjusted total on the Tax Summary and in the PDF used to read $0.00, which says
  gluten-free costs nothing extra. It now shows "—", meaning there is nothing to compare. The
  Export screen already did this, and the Tax Summary's average card now does too.

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

1. **Check a receipt with a multi-quantity item.** Open a verified receipt where one of the pairs
   has a quantity above 1. The product rows should add up to the Package Price Differential Total.
2. **Try a year with no sizes.** On the Tax Summary, pick a year where none of your products have
   package sizes, or make a test pair without sizes in an otherwise empty year. The size-adjusted
   total and the average card beside it should both read "—", not $0.00. An export PDF for that
   year should say the same.
3. **Look for the new name.** Open a product pair that has sizes, the Tax Summary, and the Export
   screen. Each should say "Size-Adjusted Differential" where it used to say "Unit Price
   Differential", with the same amounts as before.
4. **Export a CSV and open it** in Numbers, Excel or Google Sheets. Check that every column lines
   up under its heading, that unit prices look sensible (a loaf of bread should be a dollar or two
   per 100 g, not $0.02), and that the Unit Price Basis column is filled in for pairs with sizes.
5. **If you are willing, try a different region.** In Settings → General → Language & Region, set
   the region to France, export a CSV, and open it. Prices should still read `7.99`, not `7,99`,
   and nothing should be split across two columns. Remember to set your region back afterwards.
6. **Export a PDF** and compare a few rows of the transaction table against the totals.

Nothing in this build changes your existing data, and backups from earlier builds import normally.
