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

It also writes `AppIcon.svg` there; move it here, or delete it. The wordmark (`GFPC_Logo`) on the
launch screen, onboarding and PDF cover is separate and unchanged.
