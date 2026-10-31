# App icon

`AppIcon.svg` is the master of the app icon: bold "GF" letters over a check, on brand blue
`#0000FF`. The letters are Manrope ExtraBold (weight 800, SIL Open Font License) converted to
outlines, so the icon does not depend on the font being installed.

The three PNGs in `GFPriceChecker/Assets.xcassets/AppIcon.appiconset` are rendered from the same
geometry by `render-app-icon.swift`:

| Variant | Background | Letters | Check |
|---|---|---|---|
| Light | `#0000FF` | `#FFFFFF` | `#63A6FF` |
| Dark | `#000000` | `#4390F9` | `#FFFFFF` |
| Tinted | `#000000` | `#E6E6E6` | `#8C8C8C` |

To regenerate them, download Manrope's variable font from
[google/fonts](https://github.com/google/fonts/tree/main/ofl/manrope), then:

```bash
swift docs/brand/render-app-icon.swift 'Manrope[wght].ttf' GFPriceChecker/Assets.xcassets/AppIcon.appiconset
```

It also writes `AppIcon.svg` there; move it here, or delete it.

## In-app logo

The launch screen, the onboarding welcome page and the PDF report cover all draw `AppLogo`
(`GFPriceChecker/Resources/AppLogo.swift`), which shows the `GFMonogram` image set: this
`AppIcon.svg` with the tile's corners rounded (`rx="22.5"`), kept as vector data. It is the same
file as the website's `assets/images/logos/logo.svg`. If the icon's geometry changes, regenerate
it with:

```bash
sed 's|<rect width="100" height="100" fill="#0000FF"/>|<rect width="100" height="100" rx="22.5" fill="#0000FF"/>|' \
  docs/brand/AppIcon.svg > GFPriceChecker/Assets.xcassets/GFMonogram.imageset/GFMonogram.svg
```

The italic "GF / PriceChecker" wordmark that used to sit there (`GFPC_Logo`) was removed in #100.
