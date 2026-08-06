# Wrapped geographic limits for GeoAxis

This branch (based on `geoaxis-v2-foundation`) adds periodic longitude
semantics to `GeoAxis` and separates geographic limits from projected camera
limits.

## What is included

- `LongitudeInterval(west, east)`: a wrapped longitude interval that preserves
  user intent (`160..-160`, `350..20`, `170..190`, `-190..-170`, `0..360`),
  with width, membership, canonicalisation and seam splitting.
- `geolimits!(ax, west, east, south, north)`: set geographic limits in the
  source CRS; wrapped intervals are split at the projection seam and each piece
  is projected before the camera rectangle is assembled.
- `projected_limits!(ax, xmin, xmax, ymin, ymax)`: set the projected camera
  rectangle directly.
- `xlims!` now interprets `west > east` as a wrapped interval instead of
  reversing the axis, and routes numeric longitude pairs through the
  seam-aware projection path.

## Tests

`test/wrapped_limits.jl` covers interval semantics, cylindrical and polar
wrapped limits, full-period intervals, projected limits, seam-crossing data,
reset/autolimits/tight limits and rendering.

## Known limitations

- `xlims!` with a wrapped interval and no explicit y limits falls back to the
  full latitude range; use `geolimits!` or `ylims!` to constrain latitude.
- Geographic extent tracking through interactive pan/zoom (so autolimits can be
  re-derived from the geographic viewport) is follow-up work in the interaction
  PR.
