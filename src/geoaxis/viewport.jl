#= GeoAxis v2 — geographic viewport state

`GeoViewport` keeps the *geographic* extent and the *projected* boundary separate
from Makie's camera rectangle (`axis.finallimits`). This prevents projection
decorations from contaminating autolimits and gives label/grid code a stable
geographic frame to work in.
=#

"""
    GeoViewport

State container for the geographic viewport:

- `geographic_extent`: `(lon_min, lon_max, lat_min, lat_max)` in the source CRS.
- `projected_boundary`: the full projected projection-domain outline (the spine).
- `projected_bbox`: bounding box of the projected boundary.
- `visible_boundary`: the subset of the boundary inside the current camera rectangle.
"""
struct GeoViewport
    geographic_extent::NTuple{4,Float64}
    projected_boundary::Vector{Point2d}
    projected_bbox::Rect2d
    visible_boundary::Vector{Point2d}
end

GeoViewport() = GeoViewport((-180.0, 180.0, -90.0, 90.0), Point2d[], Rect2d(), Point2d[])

function _finite_bbox(pts)
    xs = Float64[]
    ys = Float64[]
    for p in pts
        (isfinite(p[1]) && isfinite(p[2])) || continue
        push!(xs, p[1])
        push!(ys, p[2])
    end
    (isempty(xs) || isempty(ys)) && return Rect2d()
    return Rect2d(
        Vec2d(minimum(xs), minimum(ys)),
        Vec2d(maximum(xs) - minimum(xs), maximum(ys) - minimum(ys)),
    )
end

# Invert the actual projected boundary back to geographic coordinates. Prefer this
# over inverting an arbitrary rectangular camera box: a rectangle's corners are not
# generally inside the projection domain, and a wrapped longitude interval would be
# reconstructed incorrectly from a plain bbox.
function geographic_extent_from_projected(gp::GeoProjection, pts)
    lons = Float64[]
    lats = Float64[]
    for p in pts
        (isfinite(p[1]) && isfinite(p[2])) || continue
        ll = try
            gp.inverse(p)
        catch
            continue
        end
        (isfinite(ll[1]) && isfinite(ll[2])) || continue
        push!(lons, ll[1])
        push!(lats, ll[2])
    end
    (isempty(lons) || isempty(lats)) && return nothing
    return (minimum(lons), maximum(lons), minimum(lats), maximum(lats))
end

function GeoViewport(gp::GeoProjection, finallimits::Rect2d, boundary::Vector{Point2d})
    vis = [p for p in boundary if p in finallimits]
    isempty(vis) && (vis = [p for p in boundary if isfinite(p[1]) && isfinite(p[2])])
    bbox = _finite_bbox(boundary)
    geo = geographic_extent_from_projected(gp, vis)
    if geo === nothing
        # Conservative fallback: sample the rectangle through the inverse transform.
        geo = try
            mn = minimum(finallimits)
            mx = maximum(finallimits)
            (umin, umax), (vmin, vmax) =
                iterated_bounds(gp.inverse, (mn[1], mx[1]), (mn[2], mx[2]))
            (umin, umax, vmin, vmax)
        catch
            (-180.0, 180.0, -90.0, 90.0)
        end
    end
    return GeoViewport(geo, boundary, bbox, vis)
end

function update_geoviewport!(
    obs::Observable{GeoViewport},
    gp::GeoProjection,
    finallimits::Rect2d,
    boundary::Vector{Point2d},
)
    obs[] = GeoViewport(gp, finallimits, boundary)
    return obs[]
end
