# Internationalization readiness plan (Slice 13)

Goal: make the codebase *script-correct and locale-correct now* (cheap), ship
translations market-by-market later (when traction justifies each). Covers:
Arabic, Hebrew (RTL) · Mandarin, Japanese (CJK) · Hindi (Devanagari) ·
Russian/Cyrillic. English + Italian are the launch copy languages.

## Difficulty map (engineering, not translation)

| Script / lang | Direction | Real difficulties | Effort |
|---|---|---|---|
| **Cyrillic** (ru, uk, sr…) | LTR | Almost none: default fonts cover it; only quirk is rich plural rules (Russian has 3 forms) — handled by ARB/intl plurals if we write messages correctly from day 1 | Trivial |
| **Japanese** (kanji+kana) | LTR | Fonts (system fonts cover ja on Android/iOS — no bundling needed), CJK line-breaking (no spaces; Flutter's engine handles it), text tends *shorter* — layouts rarely break; no plurals at all; translation tone/politeness is the hard part, not code | Easy |
| **Mandarin** (zh) | LTR | Same CJK notes as Japanese; one product decision: Simplified (zh-Hans) first, Traditional (zh-Hant) later | Easy |
| **Hindi** (Devanagari) | LTR | Complex glyph shaping (conjuncts/matras) — Flutter's HarfBuzz shaping handles it natively; the real trap is **number grouping**: 1,00,000 (lakh) not 100,000 — must use intl locale-aware formatting everywhere money is shown | Easy–moderate |
| **Arabic / Hebrew** | **RTL** | The only structurally hard pair: mirrored layouts, **bidi text** (LTR money amounts inside RTL sentences — our expense rows are the classic case), direction-aware icons, snapshot card mirroring with the watermark held stable | Moderate |

Conclusion: RTL (ar/he) is the only work that *changes how we build*; everything
else is "write locale-correct code now, drop in translations later."

## Engineering rules (apply from now on, all new code)

1. **Directional, not absolute**: `EdgeInsetsDirectional` / `AlignmentDirectional`
   / `start|end`, never `left|right`, except for things that must not flip
   (the watermark position is a deliberate decision — see T13.4).
2. **All strings through ARB/intl** (already externalized since T2.7) with
   proper plural/select syntax, so Russian plurals and Arabic duals cost nothing later.
3. **All numbers/dates through `intl` locale formatting** — no hand-rolled
   formatting; this is what makes Hindi grouping and Arabic month names free.
4. **Money in bidi contexts**: wrap formatted amounts in Unicode directional
   isolates (U+2066/U+2069) via a helper in `money_format.dart`, so "€30" never
   shreds inside an Arabic sentence.
5. **Western digits for money everywhere** (incl. Arabic locales) — clarity for
   amounts beats numeral localization; standard fintech practice.

## Slice 13 backlog tasks

| ID | Task | Est |
|---|---|---|
| T13.1 | Directional audit: sweep all layouts for left/right → start/end, directional icons (`Icons.arrow_back` auto-flips; check custom ones) | 0.5d |
| T13.2 | Locale infrastructure: `localizationsDelegates`, `supportedLocales` (en, it + placeholders ar, he, zh, hi, ja, ru), dev-settings RTL/pseudo-locale override toggle | 0.5d |
| T13.3 | Bidi-safe money: isolate-wrapping helper in `money_format` + tests (Arabic sentence containing €/$ amounts) | 0.25d |
| T13.4 | RTL goldens: snapshot card, trip home, expense list under `Directionality.rtl` + ar locale; decide & lock watermark behavior (recommendation: wordmark position fixed, layout mirrors around it) | 0.5d |
| T13.5 | Script smoke tests: CJK / Devanagari / Cyrillic rendering, Hindi number grouping, locale date formats | 0.25d |

Total ≈ 2 dev-days. Translations are explicitly **out of scope** until a
market signal (Tally of installs by country is the trigger metric).

## Ties to other plans

- **AI theming** (`AI_THEMING_SPEC.md`): taglines are already local-language
  ("Yalla" يلا for Arabic destinations); the card must render RTL taglines
  correctly → covered by T13.4 goldens. Tagline validation gains a
  direction-agnostic length check (grapheme clusters, not chars).
- **Operator track**: multi-language audio content was a B2B requirement from
  day one — `language` field already in the Wave-4 media schema notes.
