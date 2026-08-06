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
  boxes, requested side, alignment and rotation; greedy overlap rejection with
  a deterministic local-improvement pass and `:outside`/`:inline`/`:auto`
  placement modes.
- `layout.jl` — viewport-independent `DecorationExtents` and exact
  `compute_protrusions` from visible decorations (tick marks, tick labels,
  axis labels, titles, subtitles). Hidden decorations reserve no space, and
  values are only published on material change so the layout loop converges.
- `longitude.jl` — `LongitudeInterval` for wrapped longitude extents, with
  width, membership, canonicalisation, seam splitting and projection of
  geographic extents through the active `GeoProjection`.
- `linking.jl` — geographic `GeoAxis` linking: `linkxaxes!`/`linkyaxes!`/
  `linkaxes!` share longitude/latitude extents (never projected camera
  rectangles), with PROJ-based source-CRS validation and interactive camera
  propagation through `linked_geographic_limits`.
- `caching.jl` — bounded per-axis caches (`AxisCache`) for projection
  boundaries, adaptive graticules and placed labels, plus a bounded shared
  text-measurement cache. `interaction_active` selects coarse interactive
  quality (coarser resampling, cached geometry, no label optimisation) versus
  full final quality after interaction settles.
- `boundaries.jl` — projection-domain boundary strategies selected through
  `ProjectionTraits`: analytic antimeridian/conic outlines, circular azimuthal
  horizons, spherical-polygon interrupted lobes, and an adaptive sampled-hull
  fallback. `ProjectionBoundary`/`boundary_components`/`boundary_segments`
  retain component identity for labels and spines.

## Status and follow-up work

Implemented in this milestone:

- Latest registered dependency compatibility (Makie 0.24.x, Proj 1.9,
  GeometryOps 0.1.28+, etc.).
- PR #381 correctness fixes (per-vertex line colours, single/multi polygon
  dispatch, guarded rejoin, thread-safe boundary cache, exported
  `add_cyclic_point`).
- `GeoTicks(n)`, `GeoTicks(spacing = …)`, `GeoTicks(values = …)`.
- Geometry and layout regression tests (`test/geoaxis_v2.jl`).
- Wrapped longitude intervals and `geolimits!`/`projected_limits!`
  (`test/wrapped_limits.jl`).
- Geographic linking across projections, central meridians, wrapped limits and
  interactive camera changes (`test/linking.jl`).
- Cache hit/eviction and interactive-quality switching
  (`test/caching.jl`), with measurements in `benchmark/interactions.jl`.
- Boundary strategy selection, adaptive fallback, component identity and
  NaN-separated boundary segments (`test/boundaries.jl`).
- Label placement modes, local improvement and polar inline stability
  (`test/label_layout.jl`).
- Unified polar-map support: polar, azimuthal, perspective and orthographic
  maps are ordinary `GeoAxis` instances configured with a destination PROJ
  string and geographic limits. There is no separate `GeoPolarAxis` type.

## Polar maps through `GeoAxis`

A polar map is a normal geographic map using a polar, azimuthal,
stereographic, perspective, or related PROJ projection. The public type is
always `GeoAxis`:

```julia
GeoAxis(fig[1, 1];
    dest = "+proj=stere +lat_0=90 +lon_0=0 +datum=WGS84",
    limits = (-180, 180, 60, 90))
```

The same implementation handles north/south polar caps, polar stereographic,
Lambert azimuthal equal-area, orthographic polar views, circular or
projection-specific boundaries, longitude labels around the boundary, latitude
labels on parallels, regional caps, clipping, limits, layout, zooming and
panning.

### Migration note

Polar geographic maps are represented using `GeoAxis` with an appropriate
destination projection and geographic extent. `GeoPolarAxis` has been removed
because it duplicated `GeoAxis` functionality.

Deferred to later pull requests:

- Full longitude-wrapping APIs (`lonlims!`/`latlims!` with wrapped intervals).
- `linkaxes!` support for `GeoAxis`.
- Advanced inline labels and interaction-performance work.
- Exact square boundaries for Spilhaus/Adams-square projections (rounded
  corners remain, documented in the sphere-clip registry).

Relevant upstream issues tracked by this work: #350 (tick label alignment),
#349 (column gap with hidden y tick labels), #317 (labels overlapped by axis),
#268 (excessive whitespace), #221 (x/y labels), #190 (ticks inside map), #134
(missing tick labels), #344 (GLMakie jump/StackOverflow), #330 (infinite
recursion), #321 (`linkaxes!`), #122 (subplot extent cropping), #110
(interaction performance).
