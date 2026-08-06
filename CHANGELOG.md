# Changelog

All notable changes to this project are documented in this file.

## [0.8.0] - 2026-08-06

### Added

- `GeoPolarAxis`: a polar (pole-centred azimuthal) map block backed by a Makie
  `PolarAxis`, introduced with upstream PR #381.
- Sphere-space clipping and adaptive geographic resampling for projection
  discontinuities (`src/sphere_clip.jl`), including antimeridian handling,
  horizon clipping, interrupted/oblique lobe boundaries and seam-aware
  `surface!`/`heatmap!`/`contourf!`/`meshimage!` on a `GeoAxis`.
- `add_cyclic_point` is now exported.
- First stage of the GeoAxis v2 refactor: internal `GeoProjection` metadata,
  a `GeoViewport` state container, an adaptive graticule engine, boundary-aware
  tick-label placement and exact decoration protrusions.

### Changed

- `GeoAxis` gridline default alpha now matches a normal Makie `Axis`
  (`0.12`), and the projection-domain spine is drawn by default.
- `heatmap!` on a `GeoAxis` now renders as a projected, seam-clipped,
  vertex-coloured mesh (cell-centre semantics) instead of a flat lon/lat
  image; see `docs/src/architecture.md`.
- The test dependency on `CairoMakie` is removed from the package `[deps]`;
  both `CairoMakie` and `GLMakie` remain test-only dependencies.

### Fixed

- Per-vertex line colours on the seam-aware `lines!` path no longer error
  after resampling changes the vertex count.
- Seam splitting now covers single `Polygon`, `MultiPolygon` and vectors of
  `MultiPolygon` arguments, not only vectors of `Polygon`.
- The antimeridian/circle `_rejoin` walk has the same runaway-iteration guard
  as the polygon-clip rejoin.
- `GeoPolarAxis` attributes are documented as initialization-only (full
  reactivity is follow-up work).

