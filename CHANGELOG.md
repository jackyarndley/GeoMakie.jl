# Changelog

All notable changes to this project are documented in this file.

## [0.8.0] - 2026-08-06

### Added

- Unified polar-map support through `GeoAxis`: polar, azimuthal, perspective
  and orthographic maps are configured with a destination PROJ string and
  geographic limits (for example `"+proj=stere +lat_0=90 +lon_0=0"` with
  `limits = (-180, 180, 60, 90)`), reusing the standard boundary, graticule,
  label, layout and interaction systems.
- Sphere-space clipping and adaptive geographic resampling for projection
  discontinuities (`src/sphere_clip.jl`), including antimeridian handling,
  horizon clipping, interrupted/oblique lobe boundaries and seam-aware
  `surface!`/`heatmap!`/`contourf!`/`meshimage!` on a `GeoAxis`.
- `add_cyclic_point` is now exported.
- The `GeoTicks` interface is complete: `GeoTicks(6)`,
  `GeoTicks(spacing = 15)` and `GeoTicks(values = -180:30:180)` are all
  supported through the Makie tick interface.
- First stage of the GeoAxis v2 refactor: internal `GeoProjection` metadata,
  a `GeoViewport` state container, an adaptive graticule engine, boundary-aware
  tick-label placement and exact decoration protrusions.
- Wrapped longitude intervals (`LongitudeInterval`) and geographic limit APIs:
  `geolimits!(ax, west, east, south, north)` and
  `projected_limits!(ax, xmin, xmax, ymin, ymax)`.
- Geographic `GeoAxis` linking: `linkxaxes!`, `linkyaxes!`, `linkaxes!` and
  `unlinkaxes!` share geographic extents between axes while each axis projects
  independently.
- Bounded per-axis caches for projection boundaries, adaptive graticules and
  placed label candidates, plus a bounded thread-safe text-measurement cache.
- Two-quality interaction rendering: interactive frames use coarser
  resampling, cached geometry and deduplicated (non-optimised) labels; final
  frames rerun full resampling and label placement once interaction settles.
- `benchmark/interactions.jl` for construction, graticule, label, resize,
  pan/zoom, projection-change and nine-panel measurements.
- Projection-domain boundary strategies (`AnalyticBoundary`,
  `CircularBoundary`, `SphericalPolygonBoundary`, `AdaptiveBoundary`) selected
  through `ProjectionTraits`, with component identity (`ProjectionBoundary`,
  `boundary_components`, `boundary_segments`) and a robust adaptive fallback
  for projections without analytic outlines (e.g. Guyou).
- Label placement modes: `xticklabelplacement`/`yticklabelplacement` accept
  `:outside` (default), `:inline` (labels on/near graticules inside the map,
  rotated to follow curve tangents) and `:auto` (outside). `LabelCandidate`
  now carries tangent, boundary tangent, preferred side and placement class,
  and a deterministic local-improvement pass shifts rejected labels along the
  boundary to keep more of them.
- Axis-parity audit and migration notes (`docs/src/axis_parity.md`,
  `docs/src/migration.md`), and copied Makie-private compatibility code
  isolated in `src/geoaxis/makie_compat.jl`.
- CI now covers the minimum/latest Julia releases, nightly (allowed failure),
  the oldest permitted direct dependencies, every supported Makie series, and
  both CairoMakie and GLMakie backends.

### Changed

- `GeoAxis` gridline default alpha now matches a normal Makie `Axis`
  (`0.12`), and the projection-domain spine is drawn by default.
- `heatmap!` on a `GeoAxis` now renders as a projected, seam-clipped,
  vertex-coloured mesh (cell-centre semantics) instead of a flat lon/lat
  image; see `docs/src/architecture.md`.
- The test dependency on `CairoMakie` is removed from the package `[deps]`;
  both `CairoMakie` and `GLMakie` remain test-only dependencies.
- `xlims!` on a `GeoAxis` interprets `west > east` as a wrapped interval
  crossing the antimeridian (e.g. `xlims!(ax, 160, -160)`) instead of reversing
  the axis.

### Fixed

- Per-vertex line colours on the seam-aware `lines!` path no longer error
  after resampling changes the vertex count.
- Seam splitting now covers single `Polygon`, `MultiPolygon` and vectors of
  `MultiPolygon` arguments, not only vectors of `Polygon`.
- The antimeridian/circle `_rejoin` walk has the same runaway-iteration guard
  as the polygon-clip rejoin.

### Removed

- `GeoPolarAxis` (a separate polar axis type introduced by upstream PR #381).
  Polar geographic maps are represented using `GeoAxis` with an appropriate
  destination projection and geographic extent; `GeoPolarAxis` duplicated
  `GeoAxis` functionality.
