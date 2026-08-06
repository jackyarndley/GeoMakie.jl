# Projection-domain boundary strategies for GeoAxis

This branch (based on `geoaxis-v2-interactions`) introduces explicit boundary
strategies selected through `ProjectionTraits`.

## Strategies

- `AnalyticBoundary` — antimeridian/conic seam outlines (cylindrical and
  pseudocylindrical projections, Mercator pole clamps, conic cutoffs).
- `CircularBoundary` — exact circular horizon limbs for azimuthal and
  perspective projections.
- `SphericalPolygonBoundary` — interrupted/oblique spherical polygon
  boundaries with per-ring component identity.
- `AdaptiveBoundary` — robust fallback that projects a dense geographic grid
  and takes the convex hull of the finite points. This gives Guyou and unknown
  custom pipelines a finite, frameable outline where PROJ provides no analytic
  boundary.

`ProjectionBoundary` retains component identity; `boundary_components` returns
per-component point vectors and `boundary_segments` returns NaN-separated
paths for spine drawing. `boundary_points(gp::GeoProjection)` remains the
finite flattened API.

## Tests

`test/boundaries.jl` covers strategy selection, adaptive fallback, component
identity, NaN separators, circular radius consistency and analytic finiteness.
