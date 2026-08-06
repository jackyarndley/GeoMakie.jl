#= GeoAxis v2 — boundary-aware tick labels

Label candidates are built from actual boundary intersections, the outward
boundary normal, tick length, tick-label padding, actual Makie text measurements,
the requested axis side, and requested alignment/rotation. Overlapping candidates
are rejected greedily; duplicates are avoided unless explicitly requested.
=#

"""
    LabelCandidate

A candidate tick label attached to a specific boundary component:
- `tick_id`: index of the tick value in the user/auto tick vector.
- `position_px`: anchor position in pixel space.
- `rotation`: counterclockwise label rotation in radians.
- `alignment`: `(halign, valign)`.
- `bbox_px`: actual measured rotated text bounding box.
- `boundary_component`: boundary segment/polygon the label attaches to.
- `boundary_arclength`: normalised arc position along that component (0..1).
- `score`: sort key used for stable placement (smaller = preferred).
- `text`: the rendered label string.
"""
struct LabelCandidate
    tick_id::Int
    position_px::Point2d
    rotation::Float64
    alignment::Tuple{Symbol, Symbol}
    bbox_px::Rect2d
    boundary_component::Int
    boundary_arclength::Float64
    score::Float64
    text::String
end

function _rotated_bbox(bb::Rect2d, θ::Real)
    θ == 0 && return bb
    c = cos(θ); s = sin(θ)
    o = minimum(bb); w = widths(bb)
    corners = (
        Point2d(o[1], o[2]), Point2d(o[1] + w[1], o[2]),
        Point2d(o[1], o[2] + w[2]), Point2d(o[1] + w[1], o[2] + w[2]),
    )
    rx = [c * p[1] - s * p[2] for p in corners]
    ry = [s * p[1] + c * p[2] for p in corners]
    xmin, xmax = extrema(rx); ymin, ymax = extrema(ry)
    return Rect2d(Vec2d(xmin, ymin), Vec2d(xmax - xmin, ymax - ymin))
end

function _tick_label_string(value::Real, kind::Symbol, format)
    if format === Makie.automatic || format === nothing
        return kind === :meridian ? longitude_format([Float64(value)])[1] :
            latitude_format([Float64(value)])[1]
    elseif format isa Function
        out = format([value])
        return out isa AbstractVector ? string(first(out)) : string(out)
    else
        return string(value)
    end
end

function _text_bbox(str::AbstractString, font, fonts, size::Real)
    nfont = font isa Symbol ?
        (fonts === nothing ? Makie.defaultfont() : Makie.to_font(fonts, font)) :
        Makie.to_font(font)
    return Makie.text_bb(str, nfont, size)
end

# Outward unit normal of the boundary at `px` (nearest boundary segment), flipped
# to point away from the boundary centroid. Falls back to a normal from `dir` when
# no boundary is available.
function _outward_normal(px::Point2d, boundary::Vector{Point2d})
    length(boundary) >= 2 || return Point2d(0.0, -1.0)
    cx = sum(p -> p[1], boundary) / length(boundary)
    cy = sum(p -> p[2], boundary) / length(boundary)
    best = Inf; n = Point2d(0.0, -1.0)
    for i in 2:length(boundary)
        a = boundary[i - 1]; b = boundary[i]
        # distance from px to segment a-b
        ab = b .- a; L2 = dot(ab, ab)
        t = L2 == 0 ? 0.0 : clamp(dot(px .- a, ab) / L2, 0.0, 1.0)
        q = a .+ t .* ab
        d = norm(px .- q)
        if d < best
            best = d
            raw = Point2d(-ab[2], ab[1])
            n = norm(raw) > 0 ? raw ./ norm(raw) : n
            dot(n, Point2d(px[1] - cx, px[2] - cy)) < 0 && (n = -n)
        end
    end
    return n
end

function _default_alignment(n::Point2d)
    halign = n[1] > 0.5 ? :left : n[1] < -0.5 ? :right : :center
    valign = n[2] > 0.5 ? :bottom : n[2] < -0.5 ? :top : :center
    return (halign, valign)
end

"""
    label_candidate(tick_id, point_px, text, font, fontsize, rotation,
        alignment, boundary_component, boundary_arclength)

Build one candidate with an actual measured pixel-space bounding box.
"""
function label_candidate(tick_id::Int, point_px::Point2d, text::String,
        font, fontsize::Real, rotation::Real,
        alignment::Tuple{Symbol, Symbol}, boundary_component::Int,
        boundary_arclength::Float64)
    bb = Makie.text_bb(text, font, fontsize)
    w = widths(bb)
    # Anchor the measured text box at the candidate position (centred); overlap
    # rejection then compares labels where they actually sit on screen.
    rel = _rotated_bbox(Rect2d(Vec2d(-w[1] / 2, -w[2] / 2), w), rotation)
    bbox_px = Rect2d(Vec2d(minimum(rel) .+ Vec2d(point_px[1], point_px[2])), widths(rel))
    # Small positive penalty away from the map centre keeps ties deterministic.
    score = boundary_arclength + 1.0e-6 * boundary_component
    return LabelCandidate(tick_id, point_px, Float64(rotation), alignment,
        bbox_px, boundary_component, boundary_arclength, score, text)
end

"""
    place_graticule_labels(curves, ticks, kind, boundary_px;
        side, ticklabelpad, ticksize, tickalign, rotation, alignment,
        font, fontsize, format, allow_duplicates=false)

Place labels for graticule curves of one `kind` along the visible projected
boundary `boundary_px` (pixel space). Returns `Vector{LabelCandidate}` with
non-overlapping, deduplicated candidates placed outside the boundary.
"""
function place_graticule_labels(curves::Vector{GraticuleCurve}, ticks, kind::Symbol,
        boundary_px::Vector{Point2d};
        side::Symbol = kind === :meridian ? :bottom : :left,
        ticklabelpad::Real = 5.0, ticksize::Real = 6.0, tickalign::Real = 0.0,
        rotation::Real = 0.0, alignment = Makie.automatic,
        font = :regular, fonts = nothing, fontsize::Real = 16.0,
        format = Makie.automatic,
        allow_duplicates::Bool = false)
    isempty(boundary_px) && return LabelCandidate[]
    isempty(curves) && return LabelCandidate[]
    if isempty(boundary_px[1]) || length(boundary_px) < 3
        return LabelCandidate[]
    end
    center = Point2d(
        sum(p -> p[1], boundary_px) / length(boundary_px),
        sum(p -> p[2], boundary_px) / length(boundary_px),
    )
    candidates = Tuple{LabelCandidate, Bool}[]   # (candidate, side_matches)
    for curve in curves
        curve.kind == kind || continue
        tick_id = findfirst(≈(curve.coordinate), ticks)
        tick_id === nothing && continue
        for (px, comp, arc) in graticule_boundary_intersections(curve, boundary_px)
            n = _outward_normal(px, boundary_px)
            # Prefer the requested side; accept the intersection only when the
            # outward normal points that way (with a tolerance for curved spines).
            side_matches = side === :bottom ? n[2] < -0.1 :
                side === :top ? n[2] > 0.1 :
                side === :left ? n[1] < -0.1 :
                side === :right ? n[1] > 0.1 : true
            pos = px .+ n .* (ticksize * (1.0 - tickalign) + ticklabelpad)
            text = _tick_label_string(curve.coordinate, kind, format)
            align = alignment === Makie.automatic ? _default_alignment(n) : alignment
            nfont = font isa Symbol ?
                (fonts === nothing ? Makie.defaultfont() : Makie.to_font(fonts, font)) :
                Makie.to_font(font)
            cand = label_candidate(tick_id, Point2d(pos...), text, nfont,
                fontsize, rotation, align, comp, arc)
            push!(candidates, (cand, side_matches))
            break   # one label per curve by default
        end
    end
    # Prefer the requested axis side; fall back to every boundary intersection when
    # the requested side has none (e.g. a full-disk azimuthal map where labels can
    # only sit at left/right).
    matching = [c for (c, ok) in candidates if ok]
    chosen = isempty(matching) ? [c for (c, _) in candidates] : matching
    # Stable greedy overlap rejection: sort by boundary arclength so labels on the
    # same boundary component place in a deterministic order.
    sort!(chosen; by = c -> (c.boundary_component, c.boundary_arclength))
    accepted = LabelCandidate[]
    seen = Set{Int}()
    for cand in chosen
        (cand.tick_id in seen && !allow_duplicates) && continue
        overlaps = any(accepted) do a
            xoverlap = max(0.0,
                min(a.bbox_px.origin[1] + a.bbox_px.widths[1], cand.bbox_px.origin[1] + cand.bbox_px.widths[1]) -
                max(a.bbox_px.origin[1], cand.bbox_px.origin[1]))
            yoverlap = max(0.0,
                min(a.bbox_px.origin[2] + a.bbox_px.widths[2], cand.bbox_px.origin[2] + cand.bbox_px.widths[2]) -
                max(a.bbox_px.origin[2], cand.bbox_px.origin[2]))
            xoverlap > 2.0 && yoverlap > 2.0
        end
        if !overlaps
            push!(accepted, cand)
            push!(seen, cand.tick_id)
        end
    end
    return accepted
end

function renderable_label_data(candidates::Vector{LabelCandidate})
    positions = Point2d[c.position_px for c in candidates]
    texts = String[c.text for c in candidates]
    aligns = Tuple{Symbol, Symbol}[c.alignment for c in candidates]
    rotations = Float64[c.rotation for c in candidates]
    return positions, texts, aligns, rotations
end
