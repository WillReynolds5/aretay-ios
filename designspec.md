Here's the full spec for the 3D lockup:

**Brand mark — "aretay"**
- Font: Montserrat Light (300), lowercase
- Size: 0.63× the caps-line size (24px on the 941px-wide image)
- Letter-spacing: 0.45em
- Color: `#CDD5EC` (pale blue-white)

**Line 1 — "Learn Anything."**
- Font: Libre Caslon Text Italic (400), sentence case with period
- Size: 1.8× the caps-line size (66px as rendered)
- Letter-spacing: none (natural)
- Color: `#F5F2EA` (warm ivory)

**Line 2 — "BECOME EXTRAORDINARY"**
- Font: Montserrat Medium (500), all caps
- Size: sized so the line spans ~80% of canvas width (36px as rendered)
- Letter-spacing: 0.34em
- Color: `#F0D9A8` (soft gold)

**Vertical rhythm** (measured baseline-to-top of next element, relative to caps size *S*)
- aretay → Line 1 gap: ~1.15×S (42px)
- Line 1 → Line 2 gap: ~0.95×S (34px)
- All three elements center-aligned on the same vertical axis

**Legibility shadow**
- Duplicate of all text in `#0A0C1E` at ~78% opacity
- Gaussian blur: 7px (≈0.2×S), offset 0,0
- Sits beneath the crisp text layer

**Scaling rule of thumb:** everything keys off the caps line. Set "BECOME EXTRAORDINARY" to fill ~80% of your canvas width at 0.34em tracking, then derive the others: italic serif = 1.8× that size, brand mark = 0.63×, and scale the blur and gaps proportionally.

For CSS use, the Google Fonts imports are `Libre+Caslon+Text:ital@1` and `Montserrat:wght@300;500`. If you ever need a fallback stack: `'Libre Caslon Text', Georgia, serif` and `'Montserrat', 'Helvetica Neue', sans-serif`./


Image for background: e23d1736-dee0-4cdc-9298-17b67b86c549.png