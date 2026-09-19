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

**Nothing new to test.** This build exists to clear two App Store upload checks, and no
functionality changed.

If you have time, a quick confirmation that the app still launches and your existing data is
intact is enough. Build 9's testing requests still stand if you have not got to them — in
particular, **receipts showing a quantity multiplier** (lines like "2 @ $3.99", "2 X 3.99", or a
count on its own line above the item). Photos of those are still the most useful thing you can
send us; automatic quantity detection is being built next and we need real examples of how
different shops print it.
