#= GeoAxis v2 — projection metadata

`GeoProjection` is the internal wrapper around `Proj.Transformation` that GeoAxis
uses for everything geometric. It pairs the forward/inverse PROJ transforms with
`ProjectionTraits`, a small table of visual/geometric properties that would
otherwise require scattered PROJ-string parsing (family, clip strategy, seam
longitudes, singular latitudes). PROJ remains the authoritative projection and
CRS backend: GeoMakie only decides *where* to clip, resample, and draw.
=#

const Rect2d = Rect2{Float64}

# The PROJ definition string of a transformation, or `""` when unavailable.
function _proj_definition(t::Proj.Transformation)
    info = Proj.proj_pj_info(t.pj)
    info.definition == C_NULL && return ""
    return unsafe_string(info.definition)
end

"""
    ProjectionTraits

Centralised, conservative metadata about a destination projection. GeoMakie code
should consult these traits instead of parsing PROJ strings ad hoc; PROJ itself
remains responsible for all projection mathematics.
"""
struct ProjectionTraits
    family::Symbol
    clip_strategy::SphereClip
    boundary_strategy::Symbol
    longitude_periodic::Bool
    seam_longitudes::Vector{Float64}
    singular_latitudes::Vector{Float64}
end

function ProjectionTraits(t::Proj.Transformation)
    clip = clip_strategy(t)
    if clip isa NoClip
        return ProjectionTraits(:continuous, clip, :none, true, Float64[], Float64[])
    elseif clip isa AntimeridianClip
        seams = Float64[clip.lon0 - 180.0, clip.lon0 + 180.0]
        sing = clip.lat_max < 90.0 ? Float64[-clip.lat_max, clip.lat_max] : Float64[]
        return ProjectionTraits(:seamed, clip, :antimeridian, true, seams, sing)
    elseif clip isa ObliqueAntimeridianClip
        return ProjectionTraits(:oblique_seamed, clip, :rotated_antimeridian,
            true, Float64[-180.0, 180.0], Float64[])
    elseif clip isa CircleClip
        return ProjectionTraits(:azimuthal_or_perspective, clip, :horizon,
            true, Float64[], Float64[])
    elseif clip isa PolygonClip
        # Interrupted projections are periodic in longitude per lobe, but not as a
        # single global interval; mark them non-periodic for conservative wrapping.
        return ProjectionTraits(:interrupted, clip, :lobes,
            false, Float64[-180.0, 180.0], Float64[])
    elseif clip isa ProjectedClip
        return ProjectionTraits(:projected_jump, clip, :projected_jump,
            true, Float64[], Float64[])
    else
        # Conservative fallback for unknown/custom pipelines: assume a longitude
        # seam exists and let the generic clip machinery do its best.
        return ProjectionTraits(:custom, clip, :antimeridian,
            true, Float64[-180.0, 180.0], Float64[])
    end
end

"""
    GeoProjection(dest, source)

Forward/inverse `Proj.Transformation` pair with `always_xy = true`, plus
`ProjectionTraits`. `source`/`destination` retain the caller's CRS input forms
(PROJ string, GeoFormatTypes object, or an `Observable` of either).
"""
struct GeoProjection
    forward::Proj.Transformation
    inverse::Proj.Transformation
    source
    destination
    traits::ProjectionTraits
end

function GeoProjection(dest, source)
    fwd = create_transform(dest, source)
    inv = Base.inv(fwd; always_xy = true)
    return GeoProjection(fwd, inv, source, dest, ProjectionTraits(fwd))
end

# Small, lock-protected cache for string-keyed projections (GFT objects and
# Observables are still constructed on demand; they are cheap relative to PROJ).
const _GEO_PROJECTION_CACHE = Dict{Tuple{Any, Any}, GeoProjection}()
const _GEO_PROJECTION_CACHE_LOCK = ReentrantLock()

function geoprojection(dest, source)
    key = (dest, source)
    lock(_GEO_PROJECTION_CACHE_LOCK) do
        get!(() -> GeoProjection(dest, source), _GEO_PROJECTION_CACHE, key)
    end
end

create_geoprojection(dest, source) = geoprojection(dest, source)

# Projector closures work on both `GeoProjection` and raw `Proj.Transformation`;
# the GeoAxis v2 paths use the wrapper, legacy code can keep using raw transforms.
_projector(gp::GeoProjection) = _projector(gp.forward)
_inverse_projector(gp::GeoProjection) = _projector(gp.inverse)
clip_strategy(gp::GeoProjection) = gp.traits.clip_strategy
boundary_points(gp::GeoProjection) = boundary_points(gp.destination, gp.source)
