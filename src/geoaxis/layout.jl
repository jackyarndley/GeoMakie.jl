#= GeoAxis v2 — exact decoration protrusions

Layout protrusions are computed from the actual visible pixel-space bounding
boxes of tick marks, tick labels, axis labels, titles and subtitles. Hidden
decorations contribute nothing. Values are only published when they change
materially, so the layout loop can converge instead of oscillating.
=#

"""
    DecorationExtents

Viewport-independent per-side layout extents (in pixels) of the visible axis
decorations: tick marks, tick labels, axis labels. Titles/subtitles are added by
[`compute_protrusions`](@ref). Hidden decorations contribute nothing.
"""
mutable struct DecorationExtents
    left::Float64
    right::Float64
    bottom::Float64
    top::Float64
end

DecorationExtents() = DecorationExtents(0.0, 0.0, 0.0, 0.0)

function add_extent!(e::DecorationExtents, side::Symbol, value::Real)
    value <= 0 && return e
    if side === :left
        e.left = max(e.left, value)
    elseif side === :right
        e.right = max(e.right, value)
    elseif side === :bottom
        e.bottom = max(e.bottom, value)
    else
        e.top = max(e.top, value)
    end
    return e
end

function same_extents(a::DecorationExtents, b::DecorationExtents; tol::Real = 0.25)
    return all(abs(getfield(a, s) - getfield(b, s)) <= tol for s in (:left, :right, :bottom, :top))
end

_quantized_rect(r::Rect2{T}) where {T} =
    Rect2i(round.(Int, minimum(r)), round.(Int, widths(r)))

"""
    compute_protrusions(title, titlesize, titlegap, titlevisible,
        decoration_extents,
        subtitle, subtitlevisible, subtitlesize, subtitlegap,
        titlelineheight, subtitlelineheight, subtitlet, titlet)

Exact protrusions for a GeoAxis. Titles/subtitles are measured from their actual
Makie text plots; tick labels, tick marks and axis labels come from
`decoration_extents` (viewport-independent and already filtered by visibility).
"""
function compute_protrusions(title, titlesize, titlegap, titlevisible,
        decoration_extents::DecorationExtents,
        subtitle, subtitlevisible, subtitlesize, subtitlegap,
        titlelineheight, subtitlelineheight, subtitlet, titlet)
    titleheight = Makie.boundingbox(titlet, :data).widths[2] + titlegap
    subtitleheight = Makie.boundingbox(subtitlet, :data).widths[2] + subtitlegap
    titlespace = (!titlevisible || Makie.iswhitespace(title)) ? 0.0f0 : titleheight
    subtitlespace = (!subtitlevisible || Makie.iswhitespace(subtitle)) ? 0.0f0 : subtitleheight
    return GridLayoutBase.RectSides{Float32}(
        Float32(decoration_extents.left), Float32(decoration_extents.right),
        Float32(decoration_extents.bottom),
        Float32(decoration_extents.top + titlespace + subtitlespace))
end

# Tick-mark segments (pixel space) for one spine side, extended along the outward
# normal by the visible tick size. `ticksize` is the total mark length;
# `tickalign` fraction is drawn inside the boundary (we only need the outside part
# for protrusions and rendering).
function tick_segments(spines, viewport::Rect2d, ticksize::Real, tickalign::Real)
    segs = Point2d[]
    isempty(spines) && return segs
    center = Point2d(viewport.origin[1] + viewport.widths[1] / 2,
        viewport.origin[2] + viewport.widths[2] / 2)
    for p in spines
        # Use the stored boundary/limit-rect edge direction and flip it away from
        # the viewport centre so the visible tick always points outward.
        # Skip projections that are not yet camera-consistent (pre-layout pixel
        # values can be astronomically far from the viewport).
        norm(p.projected .- center) > 1.0e6 && continue
        n = isfinite(p.intersect_dir[1]) ?
            normalize(Point2d(-p.intersect_dir[2], p.intersect_dir[1])) :
            normalize(p.dir)
        dot(n, p.projected .- center) < 0 && (n = -n)
        push!(segs, p.projected)
        push!(segs, p.projected .+ n .* (ticksize * (1.0 - tickalign)))
    end
    return segs
end
