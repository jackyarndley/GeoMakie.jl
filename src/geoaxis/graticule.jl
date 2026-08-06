#= GeoAxis v2 — adaptive graticule engine

Graticule generation is separated from label placement: `GraticuleCurve` carries
the geographic geometry, the projected geometry (after the shared sphere-clip /
adaptive-resampling pipeline), and its intersections with the visible projection
boundary. Gridline visibility is independent of label visibility; rejected labels
never remove their graticule.
=#

"""
    GraticuleCurve

One meridian (`kind = :meridian`) or parallel (`kind = :parallel`) graticule.
`geographic_geometry` is the sampled lon/lat input; `projected_geometry` is the
clipped/resampled geometry in projected space (NaN-separated pieces).
"""
mutable struct GraticuleCurve
    coordinate::Float64
    kind::Symbol
    geographic_geometry::Vector{Point2d}
    projected_geometry::Vector{Point2d}
end

GraticuleCurve(coordinate, kind, geographic_geometry) =
    GraticuleCurve(coordinate, kind, geographic_geometry, Point2d[])

# Densely sample one meridian/parallel across the visible geographic extent. The
# base sampling only needs to capture the topology; `split_resample_line` performs
# the adaptive densification that determines actual geometric accuracy.
function geographic_graticule(lons, lats, extent::NTuple{4, Float64}; n = 121)
    lonlo, lonhi, latlo, lathi = extent
    curves = GraticuleCurve[]
    for lon in lons
        pts = Point2d[Point2d(lon, lat) for lat in range(latlo, lathi; length = n)]
        push!(curves, GraticuleCurve(Float64(lon), :meridian, pts))
    end
    for lat in lats
        pts = Point2d[Point2d(lon, lat) for lon in range(lonlo, lonhi; length = n)]
        push!(curves, GraticuleCurve(Float64(lat), :parallel, pts))
    end
    return curves
end

function project_graticule!(curves::Vector{GraticuleCurve}, gp::GeoProjection;
        project = _projector(gp), scale = resample_scale(project), rotated = false)
    for c in curves
        geo = split_resample_line(c.geographic_geometry, gp.forward;
            project = project, scale = scale, rotated = rotated)
        out = Point2d[]
        for p in geo
            push!(out, isnan(p[1]) ? Point2d(NaN, NaN) : Point2d(project(p[1], p[2])...))
        end
        c.projected_geometry = out
    end
    return curves
end

function generate_graticule(gp::GeoProjection, lon_ticks, lat_ticks,
        extent::NTuple{4, Float64}; kwargs...)
    curves = geographic_graticule(lon_ticks, lat_ticks, extent)
    return project_graticule!(curves, gp; kwargs...)
end

# Project a graticule's already-projected geometry (data space) into pixel space,
# preserving NaN separators, for boundary-intersection and label placement.
function project_curves_px(curves::Vector{GraticuleCurve}, project_px)
    return GraticuleCurve[
        GraticuleCurve(c.coordinate, c.kind, c.geographic_geometry, project_px.(c.projected_geometry))
        for c in curves
    ]
end

# 2-D segment intersection; returns `(point, u)` where `u` is the fraction along
# the second (boundary) segment, or `nothing`.
function _segment_intersection2(a::Point2d, b::Point2d, c::Point2d, d::Point2d)
    r = b .- a; s = d .- c
    denom = r[1] * s[2] - r[2] * s[1]
    abs(denom) < 1.0e-12 && return nothing
    t = ((c[1] - a[1]) * s[2] - (c[2] - a[2]) * s[1]) / denom
    u = ((c[1] - a[1]) * r[2] - (c[2] - a[2]) * r[1]) / denom
    (0.0 <= t <= 1.0 && 0.0 <= u <= 1.0) || return nothing
    return (a .+ t .* r, u)
end

"""
    graticule_boundary_intersections(curve, boundary) -> Vector{Tuple{Point2d,Int,Float64}}

Intersections of a graticule's projected geometry with the projected boundary
polygon. Returns `(point, boundary_segment_index, boundary_arclength)`.
"""
function graticule_boundary_intersections(curve::GraticuleCurve, boundary::Vector{Point2d})
    length(boundary) < 2 && return Tuple{Point2d, Int, Float64}[]
    out = Tuple{Point2d, Int, Float64}[]
    # Precompute cumulative arclength so intersection `u` maps to a stable arc value.
    cumlen = zeros(Float64, length(boundary))
    for i in 2:length(boundary)
        cumlen[i] = cumlen[i - 1] + norm(boundary[i] .- boundary[i - 1])
    end
    total = cumlen[end]
    pts = curve.projected_geometry
    n = length(pts)
    for i in 2:n
        a = pts[i - 1]; b = pts[i]
        (isfinite(a[1]) && isfinite(b[1])) || continue
        for j in 2:length(boundary)
            c = boundary[j - 1]; d = boundary[j]
            ix = _segment_intersection2(a, b, c, d)
            ix === nothing && continue
            point, u = ix
            arc = (cumlen[j - 1] + u * norm(d .- c)) / max(total, 1.0e-12)
            push!(out, (point, j - 1, arc))
        end
    end
    return out
end
