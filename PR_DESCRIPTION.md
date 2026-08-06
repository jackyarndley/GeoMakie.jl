# GeoAxis v2 foundation based on upstream PR #381

This branch imports the current head of
[MakieOrg/GeoMakie.jl#381](https://github.com/MakieOrg/GeoMakie.jl/pull/381)
(sphere-space clipping + adaptive geographic resampling) and builds the first
staged GeoAxis v2 milestone on top of it.

## What is included

### PR #381 foundation

- Sphere-space pre-clipping (antimeridian, horizon, interrupted/oblique lobes,
  projection-seam handling) via `src/sphere_clip.jl`.
- Adaptive geographic resampling, spherical polygon winding, seam-aware
  `surface!`/`heatmap!`/`contourf!`/`poly!`/`lines!`/`meshimage!`.
- The projection gallery docs/examples.

### Stabilisation

- `CairoMakie` removed from `[deps]`; both backends remain test-only.
- Temporary review/tracker artifacts removed (`PR381_REVIEW.md`,
  `TODO_PROJECTIONS.md`, `HANDOFF_poles.png`).
- Version bumped to `0.8.0` with a changelog.
- Per-vertex line colours fall back safely when resampling changes vertex
  counts; seam-aware `poly!` now covers single `Polygon`, `MultiPolygon` and
  vectors of either; `_rejoin` is guarded against runaway iteration; the
  boundary cache is thread-safe; `add_cyclic_point` is exported.

### Latest dependency compatibility

Resolved and tested against the newest registered versions (see the PR
description/report): Makie 0.24.13, Proj 1.9.0, GeometryOps 0.1.42,
GeoInterface 1.6.2, GeometryBasics 0.5.11, GeoFormatTypes 0.4.5, Geodesy
1.2.0, CoordinateTransformations 0.6.4, Colors 0.13.1, ImageIO 0.6.9,
StructArrays 0.7.3, CairoMakie 0.15.13, GLMakie 0.13.13.

`Makie` is declared as `0.24.13` (all later `0.24.x` patches): earlier
`0.24.x` releases predate the compute-pipeline `map!(plot, inputs, outputs)`
API the `meshimage` recipe needs and do not propagate `PlotList` child
transformations on a `GeoAxis`, so they are not genuinely supported.

### GeoAxis v2 first milestone

- `GeoProjection`/`ProjectionTraits`: internal wrapper around
  `Proj.Transformation` with `always_xy = true`; centralised visual projection
  metadata with conservative fallbacks.
- `GeoViewport`: geographic extent, projected boundary/bbox and visible
  boundary kept separate from the camera rectangle.
- `GraticuleCurve` engine: adaptive graticules through the shared
  clipping/resampling pipeline, with boundary-intersection queries.
- Boundary-aware tick labels (`LabelCandidate`): actual boundary
  intersections, outward normals, tick length/padding, measured text boxes,
  requested side/alignment/rotation, greedy non-overlap.
- Exact, viewport-independent decoration extents for protrusions; hidden
  decorations reserve no space; material-change publication so layout
  converges.
- Complete `GeoTicks` interface: `GeoTicks(6)`, `GeoTicks(spacing = 15)`,
  `GeoTicks(values = -180:30:180)`.
- Deterministic geometry/layout regression tests.
- CI matrix: minimum/latest Julia, nightly (allowed-failure), oldest
  dependencies, every supported Makie series, CairoMakie and GLMakie backends,
  and a weekly freshness run.

### Unified polar support (no separate `GeoPolarAxis`)

`GeoPolarAxis` (inherited from upstream PR #381) has been removed. Polar maps
are ordinary `GeoAxis` instances:

```julia
GeoAxis(fig[1, 1];
    dest = "+proj=stere +lat_0=90 +lon_0=0 +datum=WGS84",
    limits = (-180, 180, 60, 90))
```

The destination PROJ string selects the projection; geographic limits select
the cap. The standard projection traits, boundary strategies, graticule
engine, boundary-aware label placement, protrusions and interactions handle
north/south polar stereographic, Lambert azimuthal equal-area, orthographic
polar views, circular boundaries, longitude labels around the boundary,
latitude labels on parallels, regional caps and full caps.

Migration note:

> Polar geographic maps are represented using `GeoAxis` with an appropriate
> destination projection and geographic extent. `GeoPolarAxis` has been
> removed because it duplicated `GeoAxis` functionality.

## Deferred

Longitude-wrapping APIs, `linkaxes!`, advanced inline labels, interaction
optimisations, and exact square-boundary projections are intentionally left
for follow-up pull requests.
