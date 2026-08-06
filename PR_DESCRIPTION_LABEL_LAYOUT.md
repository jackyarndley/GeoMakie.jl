# Advanced label layout and inline labels for GeoAxis

This branch (based on `geoaxis-v2-boundaries`) extends label placement with
placement modes and a deterministic local-improvement pass.

## Placement modes

- `xticklabelplacement = :outside` / `yticklabelplacement = :outside`
  (default): exterior labels at actual boundary intersections.
- `xticklabelplacement = :inline` / `yticklabelplacement = :inline`: labels are
  placed on/near graticules inside the map, rotated to follow the curve
  tangent, and reserve no layout protrusion.
- `:auto`: currently equivalent to `:outside`.

## Candidate information

`LabelCandidate` now carries the graticule tangent, boundary tangent, preferred
side and placement class (`:outside`/`:inline`) in addition to the existing
position/bbox/arclength/score fields.

## Deterministic conflict resolution

The existing greedy pass is followed by a deterministic local-improvement pass:
rejected exterior labels are shifted a few label widths along the boundary
tangent and re-tested against accepted labels, so more labels can be kept
without changing the stable initial ordering.

## Tests

`test/label_layout.jl` covers inline/outside/auto modes, local improvement,
polar inline stability, and GeoAxis placement attributes.
