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
        return ProjectionTraits(:continuous, clip, :adaptive, true, Float64[], Float64[])
    elseif clip isa AntimeridianClip
        seams = Float64[clip.lon0-180.0, clip.lon0+180.0]
        sing = clip.lat_max < 90.0 ? Float64[-clip.lat_max, clip.lat_max] : Float64[]
        return ProjectionTraits(:seamed, clip, :antimeridian, true, seams, sing)
    elseif clip isa ObliqueAntimeridianClip
        return ProjectionTraits(
            :oblique_seamed,
            clip,
            :rotated_antimeridian,
            true,
            Float64[-180.0, 180.0],
            Float64[],
        )
    elseif clip isa CircleClip
        return ProjectionTraits(
            :azimuthal_or_perspective,
            clip,
            :horizon,
            true,
            Float64[],
            Float64[],
        )
    elseif clip isa PolygonClip
        # Interrupted projections are periodic in longitude per lobe, but not as a
        # single global interval; mark them non-periodic for conservative wrapping.
        return ProjectionTraits(
            :interrupted,
            clip,
            :lobes,
            false,
            Float64[-180.0, 180.0],
            Float64[],
        )
    elseif clip isa ProjectedClip
        return ProjectionTraits(
            :projected_jump,
            clip,
            :adaptive,
            true,
            Float64[],
            Float64[],
        )
    else
        # Conservative fallback for unknown/custom pipelines: use the adaptive
        # sampled boundary so the map still frames itself.
        return ProjectionTraits(
            :custom,
            clip,
            :adaptive,
            true,
            Float64[-180.0, 180.0],
            Float64[],
        )
    end
end

"""
    GeoProjection(dest, source)

Forward/inverse `Proj.Transformation` pair with `always_xy = true`, plus
`ProjectionTraits`. `source`/`destination` retain the caller's CRS input forms
(PROJ string, GeoFormatTypes object, or an `Observable` of either).
"""
struct GeoProjection{S,D}
    forward::Proj.Transformation
    inverse::Proj.Transformation
    source::S
    destination::D
    traits::ProjectionTraits
end

function GeoProjection(dest, source)
    fwd = create_transform(dest, source)
    inv = Base.inv(fwd; always_xy = true)
    return GeoProjection(fwd, inv, source, dest, ProjectionTraits(fwd))
end

# Bounded, lock-protected cache for projections. Keys are canonical immutable
# CRS strings (Observables unwrapped, GFT objects stringified) so equivalent
# inputs share one entry and mutable objects are never held as dictionary keys.
const _GEO_PROJECTION_CACHE = Dict{Tuple{String,String},GeoProjection}()
const _GEO_PROJECTION_CACHE_LOCK = ReentrantLock()
const _GEO_PROJECTION_CACHE_MAX = 256

_crs_key(x) = string(to_value(x))

function geoprojection(dest, source)
    key = (_crs_key(dest), _crs_key(source))
    lock(_GEO_PROJECTION_CACHE_LOCK) do
        haskey(_GEO_PROJECTION_CACHE, key) && return _GEO_PROJECTION_CACHE[key]
        if length(_GEO_PROJECTION_CACHE) >= _GEO_PROJECTION_CACHE_MAX
            k = first(keys(_GEO_PROJECTION_CACHE))
            delete!(_GEO_PROJECTION_CACHE, k)
        end
        gp = GeoProjection(dest, source)
        _GEO_PROJECTION_CACHE[key] = gp
        return gp
    end
end

create_geoprojection(dest, source) = geoprojection(dest, source)

"""
    ProjectionRenderContext

One object describing how geometry for a destination is clipped, resampled and
displayed, so every GeoAxis render path (graticules, lines, polygons,
contours, fills, surfaces, meshes, spines) derives its frame from a single
place instead of re-selecting it inline:

- `projection`: the `GeoProjection` (forward/inverse `Proj.Transformation`).
- `clip`: the active `SphereClip` strategy.
- `geographic_transform`: the full forward transform (geographic lon/lat → projected).
- `display_transform`: the transform rotated-frame (Option B) output is drawn
  with — the centred projection for an antimeridian seam, the native centred
  projector for an oblique seam, otherwise the full transform.
- `projector`: error-safe `(lon, lat) -> (x, y)` closure of `display_transform`.
- `resample_scale`: adaptive-resampling scale for the display frame, already
  multiplied by `quality_scale`.
- `rotated`: whether seam-split output is emitted in the canonical rotated
  frame (Option B) and therefore drawn with `display_transform`.
"""
struct ProjectionRenderContext
    projection::GeoProjection
    clip::SphereClip
    geographic_transform::Any
    display_transform::Any
    projector::Any
    resample_scale::Float64
    rotated::Bool
end

function ProjectionRenderContext(dest, source; quality_scale::Real = 1.0)
    gp = geoprojection(dest, source)
    t = gp.forward
    clip = gp.traits.clip_strategy
    rotated = clip isa AntimeridianClip || clip isa ObliqueAntimeridianClip
    display = if clip isa ObliqueAntimeridianClip
        clip.centred
    elseif clip isa AntimeridianClip
        create_transform(_centred_dest(dest), source)
    else
        t
    end
    proj = _projector(display)
    return ProjectionRenderContext(
        gp,
        clip,
        t,
        display,
        proj,
        resample_scale(proj) * Float64(quality_scale),
        rotated,
    )
end

ProjectionRenderContext(gp::GeoProjection; quality_scale::Real = 1.0) =
    ProjectionRenderContext(gp.destination, gp.source; quality_scale = quality_scale)

# Projector closures work on both `GeoProjection` and raw `Proj.Transformation`;
# the GeoAxis v2 paths use the wrapper, legacy code can keep using raw transforms.
_projector(gp::GeoProjection) = _projector(gp.forward)
_inverse_projector(gp::GeoProjection) = _projector(gp.inverse)
clip_strategy(gp::GeoProjection) = gp.traits.clip_strategy
