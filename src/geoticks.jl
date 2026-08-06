#=
# GeoTicks

This file contains the implementation of geographic tickfinders.
=#

"""
    GeoTicks(n::Integer)
    GeoTicks(; spacing = 15)
    GeoTicks(; values = -180:30:180)

A tick finder optimized for geographic axes.  

## Keyword arguments

- `count`: approximate number of ticks to keep (positional `GeoTicks(6)`).
- `spacing`: fixed degree spacing between ticks.
- `values`: explicit tick values (any iterable of reals).
- `threshold`: range below which `alternate_tickfinder` is used.
- `alternate_tickfinder`: fallback for small ranges (default `WilkinsonTicks(5; k_min = 3)`).

## Behaviour

The tickfinder has four regimes:

- explicit `values` are filtered to the visible range;
- fixed `spacing` produces `dmin:spacing:dmax`;
- `|vmax - vmin| < threshold`: use the `alternate_tickfinder`;
- otherwise: find ticks in `mini:step:maxi` with `step` derived from `count`.
"""
Base.@kwdef struct GeoTicks
    "Approximate number of ticks to keep spaced, with a minimum spacing of 1."
    count::Union{Nothing, Int} = nothing
    "Fixed spacing between ticks, in degrees."
    spacing::Union{Nothing, Real} = nothing
    "Explicit tick values."
    values::Union{Nothing, AbstractVector{<: Real}} = nothing
    "The minimum distance between ticks, before the `alternate_tickfinder` is used."
    threshold::Float64 = 3
    "The tick finder to use if the range is not large enough to keep the `multiple` ticks."
    alternate_tickfinder = Makie.WilkinsonTicks(5; k_min = 3)
end

GeoTicks(n::Integer) = GeoTicks(count = Int(n))

# Satisfy the Makie tick interface
function Makie.get_tickvalues(ticks::GeoTicks, transform_func, vmin, vmax)
    return _geoticks_values(ticks, vmin, vmax)
end

function Makie.get_tickvalues(ticks::GeoTicks, vmin, vmax)
    return _geoticks_values(ticks, vmin, vmax)
end

function _geoticks_values(ticks::GeoTicks, vmin, vmax)
    lo, hi = minmax(vmin, vmax)
    if ticks.values !== nothing
        vals = Float64[Float64(v) for v in ticks.values if lo <= v <= hi]
        return isempty(vals) ? Float64[] : vals
    elseif ticks.spacing !== nothing
        s = Float64(ticks.spacing)
        s > 0 || return Float64[]
        start = ceil(lo / s) * s
        vals = collect(start:s:hi)
        # include the boundary values when they are exactly on the grid
        isempty(vals) && return Float64[]
        first(vals) ≈ lo && (vals[1] = lo)
        last(vals) ≈ hi && (vals[end] = hi)
        return vals
    end
    count = ticks.count === nothing ? 12 : ticks.count
    return geoticks(-180.0, 180.0, lo, hi;
        multiple = count, threshold = ticks.threshold,
        alternate_tickfinder = ticks.alternate_tickfinder)
end

# Below is the actual implementation for the struct described above:

"""
    geoticks(dmini, dmaxi, mini, maxi; multiple, threshold, alternate_tickfinder)

A tick finder optimized for geographic axes.  

## Keyword arguments

- `multiple::Int = 12`: The number of ticks to keep spaced, with a minimum spacing of 1.
- `threshold::Float64 = 3`: The minimum distance between ticks, before the `alternate_tickfinder` is used.
- `alternate_tickfinder = Makie.WilkinsonTicks(5; k_min = 3)`: The tick finder to use if the range is not large enough to keep the `multiple` ticks.

## Behaviour

The tickfinder has three regimes, defined by the distance between the minimum and maximum values.

- ``|vmax - vmin| < threshold``: Use the `alternate_tickfinder` to find ticks.
- ``!(\\operatorname{isfinite}(vmin) && \\operatorname{isfinite}(vmax))``: `-dvmin:30:dvmax`
- All other cases: Find ticks in the range `mini:step:maxi`, where `step` is the closest multiple of `(maxi-mini)/multiple` to `dmaxi`.
"""
function geoticks(dmini, dmaxi, mini, maxi; multiple = 12, threshold = 3, alternate_tickfinder = Makie.WilkinsonTicks(5; k_min = 3))
    if isfinite(mini) && isfinite(maxi)
            # If the range is sufficiently small, use WilkinsonTicks    
            if abs(maxi - mini) < threshold
                return Makie.get_tickvalues(alternate_tickfinder, identity, mini, maxi)
            else # there's enough space to use a kind of multiples tick
                mini, maxi = min(maxi, mini), max(maxi, mini)
                # Find the closest multiple of `(maxi-mini)/multiple` to `dmaxi`.
                # This is the step size for the ticks.
                step = max(1, closest_multiple((maxi - mini) / multiple, dmaxi))
                return dmini:step:dmaxi
            end
    else # if the range is infinite, we need to place ticks at all lon/lat combinations.
        return dmini:30:dmaxi
    end
end

"""
    closest_multiple(M, N)

Find the closest integer multiple of `M` to `N`.
"""
function closest_multiple(M, N)
    # Step 1: Find the quotient
    quotient = N ÷ M

    # Step 2: Get the multiple of M just less than or equal to N
    lower_multiple = N ÷ quotient

    # Step 3: Check if the next multiple is closer
    upper_multiple = N ÷ (quotient + 1)

    # Determine which multiple is closer to N
    if abs(N - lower_multiple) <= abs(N - upper_multiple)
        return lower_multiple
    else
        return upper_multiple
    end
end
