#= GeoAxis v2 — wrapped longitude intervals

Geographic longitude limits are periodic. `LongitudeInterval` keeps the user's
intent (which side of the antimeridian an interval crosses) without reducing it
to a plain `west <= east` rectangle.
=#

"""
    LongitudeInterval(west, east; period = 360)

A possibly wrapped longitude interval. `west`/`east` keep their user-facing
values; internally the interval is canonicalised so `east = west + width`, where
`width ∈ (0, period]`. `wrap = true` means the interval crosses the antimeridian
(e.g. `LongitudeInterval(160, -160)` covers 160°E → 180° → 160°W).

Supported constructors:

```julia
LongitudeInterval(160, -160)   # wrapped, width 40
LongitudeInterval(170, 190)    # continuous, width 20
LongitudeInterval(-190, -170)  # continuous, canonicalised to 170..190
LongitudeInterval(350, 20)     # wrapped, width 30
LongitudeInterval(0, 360)      # full period
```
"""
struct LongitudeInterval{T <: Real}
    west::T
    east::T      # west + width; may exceed west + period when wrapped
    period::T
    wrap::Bool
end

function LongitudeInterval(west::Real, east::Real; period::Real = 360)
    p = Float64(period)
    w = Float64(west); e = Float64(east)
    width_raw = e - w
    if isapprox(abs(width_raw), p; atol = 1.0e-9)
        w0 = mod(w, p)
        return LongitudeInterval(w0, w0 + p, p, false)
    elseif width_raw < 0
        w0 = mod(w, p)
        width = mod(width_raw, p)
        width == 0 && (width = p)
        return LongitudeInterval(w0, w0 + width, p, true)
    else
        w0 = mod(w, p)
        return LongitudeInterval(w0, w0 + width_raw, p, false)
    end
end

width(x::LongitudeInterval) = x.east - x.west

function Base.in(lon::Real, x::LongitudeInterval)
    isapprox(width(x), x.period; atol = 1.0e-9) && return true
    t = mod(Float64(lon) - x.west, x.period) + x.west
    return x.west <= t < x.east
end

"""
    canonicalize(lon, interval)

Map a longitude into the interval's canonical `[west, west + period)` frame.
"""
canonicalize(lon::Real, x::LongitudeInterval) =
    mod(Float64(lon) - x.west, x.period) + x.west

"""
    split_at_seam(interval, seams)

Split a longitude interval into continuous `(west, east)` pieces at the given
seam longitudes (e.g. `[-180, 180]`). A full-period interval returns one piece.
"""
function split_at_seam(x::LongitudeInterval, seams)
    isapprox(width(x), x.period; atol = 1.0e-9) &&
        return [(x.west, x.west + x.period)]
    cuts = Float64[]
    for s in seams
        c = canonicalize(s, x)
        (c > x.west && c < x.east) && push!(cuts, c)
    end
    sort!(cuts)
    # Deduplicate cuts that differ only by floating-point noise (e.g. -180 and
    # +180 canonicalise to the same value) and drop zero-width pieces.
    unique_cuts = Float64[]
    for c in cuts
        (isempty(unique_cuts) || !isapprox(c, unique_cuts[end]; atol = 1.0e-9)) &&
            push!(unique_cuts, c)
    end
    pieces = Tuple{Float64, Float64}[]
    a = x.west
    for c in unique_cuts
        c <= a + 1.0e-9 && continue
        push!(pieces, (a, c))
        a = c
    end
    x.east > a + 1.0e-9 && push!(pieces, (a, x.east))
    return pieces
end

"""
    shift(interval, lon0)

Shift the interval by `lon0` degrees, preserving its width and wrap state.
"""
function shift(x::LongitudeInterval, lon0::Real)
    d = Float64(lon0)
    return LongitudeInterval(x.west + d, x.east + d; period = x.period)
end

"""
    GeographicLimits(x, y)

User-requested geographic limits: a wrapped `LongitudeInterval` and a latitude
tuple `(south, north)`.
"""
struct GeographicLimits
    x::LongitudeInterval
    y::Tuple{Float64, Float64}
end

# Project a geographic extent through `gp`, splitting wrapped intervals at the
# projection's seams, and return the union of the projected rectangles.
function project_geographic_extent(gp::GeoProjection, x::LongitudeInterval,
        ylo::Real, yhi::Real)
    ylo = Float64(ylo); yhi = Float64(yhi)
    # Avoid zero-height camera rectangles (Makie asserts low <= high and the
    # aspect-adjustment path can invert a degenerate interval).
    if yhi - ylo < 1.0e-9
        ylo -= 0.001
        yhi += 0.001
    end
    seams = isempty(gp.traits.seam_longitudes) ?
        Float64[-180.0, 180.0] : gp.traits.seam_longitudes
    rects = Rect2d[]
    for (x0, x1) in split_at_seam(x, seams)
        x1 > x0 || continue
        r = try
            Makie.apply_transform(gp.forward,
                Rect2d(Vec2d(x0, ylo), Vec2d(x1 - x0, yhi - ylo)))
        catch
            continue
        end
        (isfinite(minimum(r)[1]) && isfinite(maximum(r)[1])) || continue
        push!(rects, r)
    end
    isempty(rects) && return nothing
    xmin = minimum(r -> minimum(r)[1], rects)
    xmax = maximum(r -> maximum(r)[1], rects)
    ymin = minimum(r -> minimum(r)[2], rects)
    ymax = maximum(r -> maximum(r)[2], rects)
    return Rect2d(Vec2d(xmin, ymin), Vec2d(xmax - xmin, ymax - ymin))
end
