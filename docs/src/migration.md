# Migration notes

## Polar maps use `GeoAxis`

Polar geographic maps are represented using `GeoAxis` with an appropriate
destination projection and geographic extent. `GeoPolarAxis` has been removed
because it duplicated `GeoAxis` functionality.

```julia
GeoAxis(fig[1, 1];
    dest = "+proj=stere +lat_0=90 +lon_0=0 +datum=WGS84",
    limits = (-180, 180, 60, 90))
```

## Wrapped longitudes and limit APIs

`xlims!(ax, west, east)` treats `west > east` as a wrapped
antimeridian-crossing interval. Use `geolimits!(ax, west, east, south, north)`
for geographic limits, or `projected_limits!(ax, xmin, xmax, ymin, ymax)` for
already-projected camera rectangles.

## Linking

`linkxaxes!`/`linkyaxes!`/`linkaxes!` share geographic extents; each axis
projects independently. `unlinkaxes!` removes axes from link groups.

## Label placement

`xticklabelplacement`/`yticklabelplacement` accept `:outside` (default),
`:inline` (labels on graticules inside the map), and `:auto` (currently
outside).

## Boundary strategies and caching

Projection-domain boundaries are produced by strategies selected through
`ProjectionTraits` (analytic, circular, spherical-polygon, adaptive).
`GeoAxis` keeps bounded per-axis caches for boundaries, graticules and labels,
and uses a coarser interactive quality level during pan/zoom/scroll.
