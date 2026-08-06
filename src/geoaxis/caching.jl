#= GeoAxis v2 — bounded per-axis caches

During interaction we reuse projection boundaries, graticules and label
candidates instead of recomputing them on every camera frame. Caches are
bounded (oldest entries evicted) and keyed by the inputs that actually change
the result, so they never grow without limit.
=#

mutable struct BoundedDict{K, V}
    data::Dict{K, V}
    order::Vector{K}
    maxsize::Int
end

BoundedDict{K, V}(maxsize::Int = 64) where {K, V} =
    BoundedDict{K, V}(Dict{K, V}(), K[], maxsize)

function _evict!(cache::BoundedDict)
    isempty(cache.order) && return
    k = popfirst!(cache.order)
    delete!(cache.data, k)
    return
end

function getcache!(cache::BoundedDict{K, V}, key, f) where {K, V}
    haskey(cache.data, key) && return cache.data[key]
    length(cache.order) >= cache.maxsize && _evict!(cache)
    value = f()
    cache.data[key] = value
    push!(cache.order, key)
    return value
end

"""
    AxisCache

Per-`GeoAxis` bounded caches for projection boundaries, adaptive graticules
and placed label candidates.
"""
struct AxisCache
    boundary::BoundedDict{Tuple{Any, Any}, Vector{Point2d}}
    graticules::BoundedDict{
        Tuple{Any, Any, NTuple{4, Float64}, Int, Int, Float64},
        Vector{GraticuleCurve}}
    labels::BoundedDict{Tuple, Vector{LabelCandidate}}
    maxsize::Int
end

function AxisCache(; maxsize::Int = 64)
    return AxisCache(
        BoundedDict{Tuple{Any, Any}, Vector{Point2d}}(maxsize),
        BoundedDict{
            Tuple{Any, Any, NTuple{4, Float64}, Int, Int, Float64},
            Vector{GraticuleCurve}}(maxsize),
        BoundedDict{Tuple, Vector{LabelCandidate}}(maxsize),
        maxsize,
    )
end

function clear_cache!(cache::AxisCache)
    empty!(cache.boundary.data); empty!(cache.boundary.order)
    empty!(cache.graticules.data); empty!(cache.graticules.order)
    empty!(cache.labels.data); empty!(cache.labels.order)
    return cache
end

# Bounded, thread-safe text-measurement cache shared by all axes (measurement
# depends only on the string/font/size triple).
const _TEXT_METRICS_CACHE =
    BoundedDict{Tuple{String, String, Float64}, Rect3{Float64}}(128)
const _TEXT_METRICS_LOCK = ReentrantLock()

function cached_text_bbox(text::AbstractString, font, fontsize::Real)
    fstr = string(font)
    key = (String(text), fstr, Float64(fontsize))
    lock(_TEXT_METRICS_LOCK) do
        return getcache!(_TEXT_METRICS_CACHE, key, () ->
            Makie.text_bb(text, font, fontsize)
        )
    end
end
