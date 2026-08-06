# Architecture

GeoMakie provides geographic plotting utility to Makie in 3 ways:

1. Defining geographic projections using Proj.jl
2. Providing a nonlinear axis specialized for geographic use called GeoAxis
3. Various utilities like coastlines, earth-image, etc.

## GeoAxis v2 (in progress)

The GeoAxis v2 refactor is staged on top of the sphere-space clipping foundation
from upstream PR #381 (`src/sphere_clip.jl`). The target architecture is:

```text
Proj.jl
   ↓
GeoProjection
   ↓
GeoViewport
   ├── geometry pipeline
   ├── graticule engine
   ├── label layout
   ├── layout/protrusions
   └── interactions
           ↓
        GeoAxis
```

Current internal modules (`src/geoaxis/`):

- `projection.jl` — `GeoProjection` (forward/inverse `Proj.Transformation` with
  `always_xy = true`) and `ProjectionTraits` (family, clip strategy, seam
  longitudes, singular latitudes). PROJ remains the authoritative projection
  and CRS backend; GeoMakie never reimplements projection mathematics.
- `viewport.jl` — `GeoViewport`, keeping the geographic extent, projected
  boundary, projected bbox and visible boundary separate from Makie's camera
  rectangle.
- `graticule.jl` — `GraticuleCurve` generation through the shared
  sphere-clip/resampling pipeline, with boundary-intersection queries.
- `labels.jl` — boundary-aware `LabelCandidate` placement using actual
  boundary intersections, outward normals, tick length/padding, measured text
  boxes, requested side, alignment and rotation; greedy overlap rejection.
- `layout.jl` — viewport-independent `DecorationExtents` and exact
  `compute_protrusions` from visible decorations (tick marks, tick labels,
  axis labels, titles, subtitles). Hidden decorations reserve no space, and
  values are only published on material change so the layout loop converges.

## Status and follow-up work

Implemented in this milestone:

- Latest registered dependency compatibility (Makie 0.24.x, Proj 1.9,
  GeometryOps 0.1.28+, etc.).
- PR #381 correctness fixes (per-vertex line colours, single/multi polygon
  dispatch, guarded rejoin, thread-safe boundary cache, exported
  `add_cyclic_point`).
- `GeoTicks(n)`, `GeoTicks(spacing = …)`, `GeoTicks(values = …)`.
- Geometry and layout regression tests (`test/geoaxis_v2.jl`).

Deferred to later pull requests:

- Full longitude-wrapping APIs (`lonlims!`/`latlims!` with wrapped intervals).
- `linkaxes!` support for `GeoAxis`.
- Advanced inline labels and interaction-performance work.
- Reactive `GeoPolarAxis` attributes.
- Exact square boundaries for Spilhaus/Adams-square projections (rounded
  corners remain, documented in the sphere-clip registry).

Relevant upstream issues tracked by this work: #350 (tick label alignment),
#349 (column gap with hidden y tick labels), #317 (labels overlapped by axis),
#268 (excessive whitespace), #221 (x/y labels), #190 (ticks inside map), #134
(missing tick labels), #344 (GLMakie jump/StackOverflow), #330 (infinite
recursion), #321 (`linkaxes!`), #122 (subplot extent cropping), #110
(interaction performance).
