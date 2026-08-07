#= GeoAxis v2 — projection-domain boundary strategies

`AbstractBoundaryStrategy` implementations describe how the visible edge of a
projection domain is obtained. Strategies are selected from `ProjectionTraits`
so boundary construction stays centralised; PROJ remains the only projection
mathematics backend.
=#

abstract type AbstractBoundaryStrategy end

"""Antimeridian/analytic seam outlines (cylindrical, pseudocylindrical, conic)."""
struct AnalyticBoundary <: AbstractBoundaryStrategy end

"""Exact circular horizon limbs (azimuthal and perspective projections)."""
struct CircularBoundary <: AbstractBoundaryStrategy end

"""Spherical polygon / interrupted lobe boundaries."""
struct SphericalPolygonBoundary <: AbstractBoundaryStrategy end

"""Robust adaptive fallback: convex hull of a projected geographic grid."""
struct AdaptiveBoundary <: AbstractBoundaryStrategy end

function boundary_strategy(gp::GeoProjection)
    s = gp.traits.boundary_strategy
    if s in (:antimeridian, :rotated_antimeridian)
        return AnalyticBoundary()
    elseif s === :horizon
        return CircularBoundary()
    elseif s === :lobes
        return SphericalPolygonBoundary()
    else
        return AdaptiveBoundary()
    end
end

"""
    ProjectionBoundary

A projection-domain boundary split into components. Component identity is
retained so labels can be placed on every component and spines can be drawn as
separate NaN-separated paths.
"""
struct ProjectionBoundary
    components::Vector{Vector{Point2d}}
end

ProjectionBoundary(pts::Vector{Point2d}) = ProjectionBoundary([pts])
ProjectionBoundary() = ProjectionBoundary(Vector{Vector{Point2d}}())

Base.length(b::ProjectionBoundary) = length(b.components)
Base.getindex(b::ProjectionBoundary, i::Int) = b.components[i]
Base.iterate(b::ProjectionBoundary, state...) = iterate(b.components, state...)

function Base.:(==)(a::ProjectionBoundary, b::ProjectionBoundary)
    length(a) == length(b) || return false
    return all(a.components[i] == b.components[i] for i in eachindex(a.components))
end

function Base.show(io::IO, b::ProjectionBoundary)
    print(io, "ProjectionBoundary(", length(b.components), " components)")
end

# Adaptive fallback: project a dense geographic grid and take the convex hull of
# the finite points. This gives a finite projected outline for projections with
# no analytic boundary (e.g. Guyou) and for unknown/custom pipelines.
function _adaptive_boundary_points(gp::GeoProjection)
    proj = _projector(gp)
    pts = Point2d[]
    for lon = -180.0:0.5:180.0, lat = -89.5:0.5:89.5
        xy = proj(lon, lat)
        (isfinite(xy[1]) && isfinite(xy[2])) && push!(pts, Point2d(xy[1], xy[2]))
    end
    length(pts) < 8 && return Point2d[]
    hull = GO.convex_hull(pts)
    return _exterior_open(hull)
end

"""
    boundary_components(gp::GeoProjection) -> Vector{Vector{Point2d}}

Projected boundary components of the projection domain.
"""
function boundary_components(gp::GeoProjection)
    strat = boundary_strategy(gp)
    if strat isa AdaptiveBoundary
        pts = _adaptive_boundary_points(gp)
        return isempty(pts) ? Vector{Vector{Point2d}}() : [pts]
    elseif strat isa SphericalPolygonBoundary
        clip = gp.traits.clip_strategy
        proj = _projector(gp)
        comps = Vector{Vector{Point2d}}()
        for ring in clip.boundary
            pts = Point2d[]
            for p in ring
                xy = proj(p[1], p[2])
                (isfinite(xy[1]) && isfinite(xy[2])) && push!(pts, Point2d(xy[1], xy[2]))
            end
            isempty(pts) || push!(comps, pts)
        end
        return comps
    else
        pts = boundary_points(gp.destination, gp.source)
        return isempty(pts) ? Vector{Vector{Point2d}}() : [pts]
    end
end

"""
    boundary_points(gp::GeoProjection) -> Vector{Point2d}

All finite projected boundary points (components concatenated). Compatible with
the legacy `boundary_points(dest, source)` API.
"""
function boundary_points(gp::GeoProjection)
    comps = boundary_components(gp)
    return reduce(vcat, comps; init = Point2d[])
end

# Flat point view of a `ProjectionBoundary` (finite projected points, components
# concatenated without separators). Used for viewport/intersection geometry.
function boundary_points(b::ProjectionBoundary)
    return reduce(vcat, b.components; init = Point2d[])
end

"""
    boundary_segments(gp::GeoProjection) -> Vector{Point2d}

NaN-separated boundary paths (one per component) ready for `lines!`.
"""
function boundary_segments(gp::GeoProjection)
    out = Point2d[]
    for comp in boundary_components(gp)
        isempty(comp) && continue
        append!(out, comp)
        length(comp) > 1 && push!(out, comp[1])   # close the ring
        push!(out, Point2d(NaN, NaN))
    end
    return out
end

# NaN-separated `lines!`-ready view of a `ProjectionBoundary` (one closed path
# per component). Used for the spine; components are never joined.
function boundary_segments(b::ProjectionBoundary)
    out = Point2d[]
    for comp in b.components
        isempty(comp) && continue
        append!(out, comp)
        length(comp) > 1 && push!(out, comp[1])   # close the ring
        push!(out, Point2d(NaN, NaN))
    end
    return out
end
