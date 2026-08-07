#= GeoAxis v2 — geographic axis linking

`linkxaxes!`/`linkyaxes!`/`linkaxes!` share *geographic* extents between
`GeoAxis` instances. Each axis keeps its own destination projection and
projects the shared geographic extent independently; projected camera
rectangles are never copied between axes.
=#

function _geo_limits_from_limits(raw)
    x = nothing
    y = nothing
    if raw isa GeographicLimits
        return raw.x, raw.y
    elseif raw isa Tuple
        mx, my = raw
        if mx isa LongitudeInterval
            x = mx
        elseif mx isa Tuple && length(mx) == 2 && all(v -> v isa Real, mx)
            x = LongitudeInterval(mx[1], mx[2])
        end
        if my isa Tuple && length(my) == 2 && all(v -> v isa Real, my)
            y = (Float64(my[1]), Float64(my[2]))
        end
    end
    return x, y
end

_same_source(a::GeoAxis, b::GeoAxis) = to_value(a.source) == to_value(b.source)

function _is_geographic_source(src)
    s = string(src)
    return occursin(r"\bproj=(longlat|latlong)\b", s) ||
           occursin(r"EPSG:?4326", s) ||
           (src isa GeoFormatTypes.EPSG && GeoFormatTypes.val(src) == 4326)
end

# Linking requires source CRSs that both describe geographic lon/lat. Validate
# by transforming the origin: geographic-to-geographic conversions must map
# (0,0) back to (≈0, ≈0).
function _compatible_geographic_source!(from, to)
    from == to && return nothing
    (_is_geographic_source(from) && _is_geographic_source(to)) || throw(
        ArgumentError(
            "Cannot link GeoAxis with incompatible source CRSs ($(from) -> $(to)): " *
            "linking currently requires geographic (lon/lat) source CRSs.",
        ),
    )
    t = try
        create_transform(to, from)
    catch e
        throw(
            ArgumentError(
                "Cannot link GeoAxis with incompatible source CRSs ($(from) -> $(to)): $(sprint(showerror, e))",
            ),
        )
    end
    p = try
        t((0.0, 0.0))
    catch
        throw(
            ArgumentError(
                "Cannot link GeoAxis with incompatible source CRSs ($(from) -> $(to)): transforming (0, 0) failed.",
            ),
        )
    end
    (
        isfinite(p[1]) &&
        isfinite(p[2]) &&
        isapprox(p[1], 0.0; atol = 1.0e-3) &&
        isapprox(p[2], 0.0; atol = 1.0e-3)
    ) || throw(
        ArgumentError(
            "Cannot link GeoAxis with incompatible source CRSs ($(from) -> $(to)): " *
            "the transformation does not preserve geographic lon/lat.",
        ),
    )
    return nothing
end

function _propagate_geographic_limits!(src::GeoAxis)
    src.block_limit_linking[] && return
    x, y = _geo_limits_from_limits(src.limits[])
    (x === nothing && y === nothing) && return
    for other in unique(vcat(src.xaxislinks, src.yaxislinks))
        other === src && continue
        linkx = other in src.xaxislinks
        linky = other in src.yaxislinks
        otherx, othery = _geo_limits_from_limits(other.limits[])
        newx = linkx ? x : otherx
        newy = linky ? y : othery
        if (linkx && x !== nothing && !_same_source(src, other)) ||
           (linky && y !== nothing && !_same_source(src, other))
            _compatible_geographic_source!(to_value(src.source), to_value(other.source))
        end
        newx === nothing && (newx = otherx)
        newy === nothing && (newy = othery)
        (newx === nothing && newy === nothing) && continue
        other.block_limit_linking[] = true
        try
            other.limits[] = (newx, newy)
        finally
            other.block_limit_linking[] = false
        end
    end
    return
end

# Approximate geographic extent of the current projected camera rectangle.
function _geographic_from_projected(src::GeoAxis)
    inv = src.inv_transform_func[]
    rect = src.targetlimits[]
    mn = minimum(rect)
    mx = maximum(rect)
    (umin, umax), (vmin, vmax) = iterated_bounds(inv, (mn[1], mx[1]), (mn[2], mx[2]))
    return LongitudeInterval(umin, umax), (vmin, vmax)
end

# Interactive pan/zoom: when the camera rectangle moves and the axis has no
# explicit geographic limits, recover the geographic extent and push it to
# linked axes. The source axis's own `limits` are left untouched (programmatic
# changes propagate through `_propagate_geographic_limits!`).
function _propagate_projected_limits!(src::GeoAxis)
    src.block_limit_linking[] && return
    src.suppress_projected_propagation[] && return
    (isempty(src.xaxislinks) && isempty(src.yaxislinks)) && return
    src.linked_geographic_limits[] !== nothing && return   # this axis follows another
    x, y = _geo_limits_from_limits(src.limits[])
    (x !== nothing || y !== nothing) && return   # explicit limits propagate via `limits`
    newx, newy = _geographic_from_projected(src)
    newlims = GeographicLimits(newx, newy)
    for other in unique(vcat(src.xaxislinks, src.yaxislinks))
        other === src && continue
        other.block_limit_linking[] = true
        try
            other.linked_geographic_limits[] = newlims
        finally
            other.block_limit_linking[] = false
        end
    end
    return
end

function _link_geoaxes!(axes::Vector{GeoAxis}, dir::Symbol)
    isempty(axes) && return
    for i = 1:length(axes), j = (i+1):length(axes)
        a = axes[i]
        b = axes[j]
        _same_source(a, b) ||
            _compatible_geographic_source!(to_value(a.source), to_value(b.source))
    end
    all_links = Set{GeoAxis}(axes)
    for ax in axes
        links = dir === :x ? ax.xaxislinks : ax.yaxislinks
        for l in links
            push!(all_links, l)
        end
    end
    for ax in all_links
        links = dir === :x ? ax.xaxislinks : ax.yaxislinks
        for other in all_links
            other === ax && continue
            other in links || push!(links, other)
        end
    end
    _propagate_geographic_limits!(first(axes))
    return
end

"""
    linkxaxes!(ax::GeoAxis, others...)
    linkyaxes!(ax::GeoAxis, others...)
    linkaxes!(ax::GeoAxis, others...)

Link the geographic extents of several `GeoAxis` instances. X links share the
longitude interval, Y links share latitude, and full links share both. Each
axis keeps its own destination projection and projects the shared geographic
extent independently.
"""
Makie.linkxaxes!(axes::Vector{GeoAxis}) = _link_geoaxes!(axes, :x)
Makie.linkxaxes!(a::GeoAxis, others::GeoAxis...) = _link_geoaxes!([a, others...], :x)
Makie.linkyaxes!(axes::Vector{GeoAxis}) = _link_geoaxes!(axes, :y)
Makie.linkyaxes!(a::GeoAxis, others::GeoAxis...) = _link_geoaxes!([a, others...], :y)
Makie.linkaxes!(axes::Vector{GeoAxis}) =
    (_link_geoaxes!(axes, :x); _link_geoaxes!(axes, :y))
Makie.linkaxes!(a::GeoAxis, others::GeoAxis...) = Makie.linkaxes!([a, others...])

"""
    unlinkaxes!(ax::GeoAxis, others...)

Remove the given axes from each other's geographic link groups. With no
`others`, `ax` is unlinked from all axes it is currently linked to.
"""
function unlinkaxes!(ax::GeoAxis, others::GeoAxis...)
    targets = isempty(others) ? unique(vcat(ax.xaxislinks, ax.yaxislinks)) : collect(others)
    for a in unique(vcat([ax], targets))
        filter!(x -> !(x in targets || x === ax), a.xaxislinks)
        filter!(y -> !(y in targets || y === ax), a.yaxislinks)
        a.linked_geographic_limits[] = nothing
    end
    return
end
