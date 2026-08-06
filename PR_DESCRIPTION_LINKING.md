# Geographic GeoAxis linking

This branch (based on `geoaxis-v2-wrapped-limits`) implements geographic
`GeoAxis` linking.

## Semantics

- `linkxaxes!(ax1, ax2, ...)` shares the longitude interval.
- `linkyaxes!(ax1, ax2, ...)` shares latitude.
- `linkaxes!(ax1, ax2, ...)` shares the full geographic extent.
- `unlinkaxes!(ax1, ax2, ...)` removes the given axes from each other's link
  groups.

Linked axes share geographic extents, not projected camera rectangles. Each
axis keeps its own destination projection and projects the shared extent
independently. Programmatic changes (`geolimits!`, `xlims!`, `ylims!`) propagate
exact geographic intervals, including wrapped antimeridian-crossing intervals.
Interactive camera changes propagate approximate geographic extents through
`linked_geographic_limits` when an axis has automatic limits.

Source CRSs must describe geographic lon/lat; incompatible sources raise a
clear `ArgumentError`.

## Tests

`test/linking.jl` covers x-only/y-only/full linking, different destination
projections, different central meridians, wrapped longitudes, programmatic and
interactive updates, unlinking, and incompatible-source errors.

## Known limitations

- Interactive propagation uses an approximate inverse of the projected camera
  rectangle; exact wrapped-interval recovery during pan/zoom is deferred to the
  interaction/caching PR.
- Linking axes with different *projected* source CRSs is rejected with a clear
  error rather than silently misinterpreting coordinates.
