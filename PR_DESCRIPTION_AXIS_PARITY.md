# GeoAxis axis parity, documentation and upstream preparation

This branch (based on `geoaxis-v2-label-layout`) completes the planned
GeoAxis v2 stack with an axis-parity audit, migration notes, and isolation of
copied Makie-private compatibility code.

## Changes

- `docs/src/axis_parity.md` classifies every audited `Axis` surface as
  Supported / Not meaningful / Deferred / Unsupported-with-clear-error.
- `docs/src/migration.md` documents the `GeoPolarAxis` removal, wrapped
  longitudes, `geolimits!`/`projected_limits!`, linking, label placement modes,
  boundary strategies and caching.
- `src/geoaxis/makie_compat.jl` isolates copied Makie-private helpers
  (`br_getindex`, `get_point_xyz`, `_point_iterator`,
  `limits_from_transformed_points`, `transformed_limits`,
  `_selection_vertices_notransform`) with original-source documentation and the
  smallest upstream API changes that would remove each copy.
- `test/axis_parity.jl` verifies the documented attribute surface.

## Remaining known limitations

- Minor ticks/minor grids are declared but not rendered.
- `backgroundcolor` is not yet implemented.
- Full inline-label collision against neighboring layout blocks is follow-up
  work.
