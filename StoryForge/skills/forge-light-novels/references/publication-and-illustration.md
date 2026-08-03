# Illustration and Publication

## Contents

1. [Illustration bible](#illustration-bible)
2. [ImageGen contract](#imagegen-contract)
3. [Publication configuration](#publication-configuration)
4. [EPUB and PDF](#epub-and-pdf)
5. [Series bible](#series-bible)

## Illustration bible

Plan illustrations after the outline passes. Lock the style, palette, lighting,
character silhouettes, recurring props, and location anchors before generating
production art. Every moment records its scene, role, narrative purpose,
emotional beat, composition, required details, forbidden details, and continuity
references.

Before release, review the entire art set on one contact sheet. Per-image review
checks composition, character consistency, continuity, eye line, accidental
lettering/artifacts, must-show delivery, and must-avoid compliance. Set-level
review checks repeated thumbnail composition, palette/lighting consistency,
scale drift, and prop drift. Bind image verdicts to asset hashes and set approval
to the ordered asset-set hash. Contact sheets are review artifacts; all new or
replacement production art still uses ImageGen.

Illustrations should reveal, reframe, or reward. Do not select only the easiest
standing conversations. Cover art must communicate the book's specific promise
at thumbnail size; interior art should capture a turn, relationship change, or
signature image.

## ImageGen contract

Use ImageGen for every production cover, interior illustration, character
design, prop sheet, or location key art. `make_imagegen_illustration_briefs.py`
turns approved scene plans into reusable prompts. Preserve generated source
images and record `source_method: imagegen`, asset path, SHA-256, reviewer, and
approval status. Programmatic drawings may be used only for tests, typography,
or proof overlays, never as substitute production art.

## Publication configuration

`publication` records language, author, edition, rights, identifier, subtitle,
cover copy, scene-break glyph, chapter-title style, trim profile, typography,
front matter, back matter, cover asset, and interior placements. Keep paths
inside the project. Bind every approved image by hash.

The publication-polish pass checks title hierarchy, chapter openings, scene
breaks, widows/orphans, page numbers, contents, metadata, cover copy, image
placement, captions, and final rendered proofs.

## EPUB and PDF

Run:

```bash
python3 scripts/build_novel_release.py novels/<slug>/novel.json
```

The builder creates deterministic EPUB and PDF artifacts under `output/`, writes
a hash report, validates EPUB structure/accessibility/text parity, checks PDF
text extraction and embedded fonts, and renders every PDF page plus a complete
contact sheet. Inspect the complete sheet before release. External EPUBCheck
runs whenever installed and becomes mandatory when
`publication.require_external_epubcheck` is true.

The PDF lane uses ReportLab and Poppler. If the active Python lacks ReportLab,
the script may select another local Python interpreter that provides it. Missing
dependencies are explicit failures, not silently degraded output.

## Series bible

Every project declares `series.mode` as `standalone` or `series`. Series volumes
record series and volume promises, volume number, incoming/outgoing continuity,
canon entries, protected mysteries, future hooks, and the protagonist's arc
position. A standalone explicitly records that it does not depend on hidden
continuity.

Run `build_series_bible.py` across a novels directory to detect duplicate volume
numbers and conflicting canon IDs, then emit a reusable catalog. Future hooks
must not make the current volume feel unfinished unless the reader promise
explicitly includes a serial cliffhanger.
