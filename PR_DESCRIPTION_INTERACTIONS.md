# Interaction and caching performance for GeoAxis

This branch (based on `geoaxis-v2-linking`) adds bounded per-axis caches and a
two-quality interaction pipeline.

## Caching

- `AxisCache` (per `GeoAxis`, bounded with oldest-entry eviction) caches:
  - projection boundaries (keyed by destination/source CRS),
  - adaptive graticules (keyed by CRS, geographic extent, tick counts and
    quality level),
  - placed label candidates (keyed by CRS, ticks, quantised viewport size,
    quality, requested sides and styling attributes).
- A bounded, thread-safe text-measurement cache removes repeated Makie text
  layout calls for unchanged labels.

## Interactive vs final quality

During active pan/zoom/scroll (`interaction_active = true`) the axis uses a
coarser adaptive-resampling scale, reuses cached graticules/boundaries, and
places labels with deduplication but without the full greedy overlap pass.
When interaction settles (mouse release or a short scroll debounce), the axis
switches back to final quality and reruns full resampling and label placement.

## Benchmarks

`benchmark/interactions.jl` reports minimum/median/mean time and allocations
for cold/warm construction, global and polar graticules, label placement,
figure resize, drag-pan, scroll-zoom, cylindrical→polar projection changes and
nine-panel figures.

## Tests

`test/caching.jl` covers bounded eviction, text-metric cache hits, per-axis
cache population/stability, interactive-quality entries and cache clearing.
