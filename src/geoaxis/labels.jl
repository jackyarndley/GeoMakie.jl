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
- `interior`: `true` for labels placed inside the map (e.g. latitude labels on
  polar parallels), `false` for exterior boundary labels.
- `side`: the layout side the label belongs to (`:left`, `:right`, `:bottom`,
  `:top`), derived from the outward boundary normal and independent of the
  current viewport.
- `tangent`: graticule tangent at the anchor (pixel space).
- `boundary_tangent`: boundary tangent at the anchor (pixel space).
- `preferred_side`: the requested axis side for this label.
- `placement_class`: `:outside` (exterior boundary label) or `:inline`
  (label placed on/near the graticule inside the map).
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
    interior::Bool
    side::Symbol
    tangent::Point2d
    boundary_tangent::Point2d
    preferred_side::Symbol
    placement_class::Symbol
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
    return cached_text_bbox(str, nfont, size)
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
        boundary_arclength::Float64;
        interior::Bool = false, side::Symbol = :bottom,
        tangent::Point2d = Point2d(0, 0), boundary_tangent::Point2d = Point2d(0, 0),
        preferred_side::Symbol = side, placement_class::Symbol = :outside)
    bb = cached_text_bbox(text, font, fontsize)
    w = widths(bb)
    # Anchor the measured text box at the candidate position (centred); overlap
    # rejection then compares labels where they actually sit on screen.
    rel = _rotated_bbox(Rect2d(Vec2d(-w[1] / 2, -w[2] / 2), w), rotation)
    bbox_px = Rect2d(Vec2d(minimum(rel) .+ Vec2d(point_px[1], point_px[2])), widths(rel))
    # Small positive penalty away from the map centre keeps ties deterministic.
    score = boundary_arclength + 1.0e-6 * boundary_component
    return LabelCandidate(tick_id, point_px, Float64(rotation), alignment,
        bbox_px, boundary_component, boundary_arclength, score, text, interior, side,
        tangent, boundary_tangent, preferred_side, placement_class)
end

function _label_side(n::Point2d)
    return abs(n[1]) >= abs(n[2]) ?
        (n[1] < 0 ? :left : :right) :
        (n[2] < 0 ? :bottom : :top)
end

# Interior candidate for a parallel that does not reach the projected boundary
# (the polar-cap case: parallels are concentric rings inside the map). The label
# is placed at the point of the parallel closest to the requested side and offset
# outward from the map centre so it reads as a latitude label on that parallel.
function _parallel_interior_candidate(curve::GraticuleCurve, tick_id::Int, side::Symbol,
        center::Point2d, ticklabelpad::Real, rotation::Real,
        alignment, font, fonts, fontsize::Real, format)
    pts = filter(p -> isfinite(p[1]) && isfinite(p[2]), curve.projected_geometry)
    isempty(pts) && return nothing
    anchor = if side === :left
        reduce((a, b) -> b[1] < a[1] ? b : a, pts)
    elseif side === :right
        reduce((a, b) -> b[1] > a[1] ? b : a, pts)
    elseif side === :top
        reduce((a, b) -> b[2] > a[2] ? b : a, pts)
    else
        reduce((a, b) -> b[2] < a[2] ? b : a, pts)
    end
    n = anchor .- center
    n = norm(n) > 1.0e-9 ? n ./ norm(n) : Point2d(1.0, 0.0)
    pos = anchor .+ n .* ticklabelpad
    tangent = _curve_tangent_at(pts, anchor)
    text = _tick_label_string(curve.coordinate, :parallel, format)
    align = alignment === Makie.automatic ? _default_alignment(n) : alignment
    nfont = font isa Symbol ?
        (fonts === nothing ? Makie.defaultfont() : Makie.to_font(fonts, font)) :
        Makie.to_font(font)
    return label_candidate(tick_id, Point2d(pos...), text, nfont, fontsize,
        rotation, align, 0, 0.0; interior = true, side = side,
        tangent = tangent, preferred_side = side, placement_class = :inline)
end

function _curve_tangent_at(pts::Vector{Point2d}, anchor::Point2d)
    length(pts) < 2 && return Point2d(1.0, 0.0)
    _, i = findmin(norm(p .- anchor) for p in pts)
    a = pts[max(i - 1, 1)]; b = pts[min(i + 1, length(pts))]
    t = b .- a
    return norm(t) > 1.0e-9 ? t ./ norm(t) : Point2d(1.0, 0.0)
end

# Inline candidate: label placed on/near the graticule itself, inside the map,
# with rotation following the curve tangent. Used by `xticklabelplacement =
# :inline` / `yticklabelplacement = :inline`.
function _inline_candidate(curve::GraticuleCurve, tick_id::Int, kind::Symbol,
        placement_pad::Real, font, fonts, fontsize::Real, format)
    pts = filter(p -> isfinite(p[1]) && isfinite(p[2]), curve.projected_geometry)
    length(pts) < 2 && return nothing
    i = cld(length(pts), 2)
    anchor = pts[i]
    tangent = _curve_tangent_at(pts, anchor)
    normal = Point2d(-tangent[2], tangent[1])
    pos = anchor .+ normal .* placement_pad
    text = _tick_label_string(curve.coordinate, kind, format)
    rotation = atan(tangent[2], tangent[1])
    nfont = font isa Symbol ?
        (fonts === nothing ? Makie.defaultfont() : Makie.to_font(fonts, font)) :
        Makie.to_font(font)
    return label_candidate(tick_id, Point2d(pos...), text, nfont, fontsize,
        rotation, (:center, :center), 0, 0.0;
        interior = true, side = :auto, tangent = tangent,
        preferred_side = :auto, placement_class = :inline)
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
        allow_duplicates::Bool = false, quality::Symbol = :final,
        placement::Symbol = :outside)
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
        if placement === :inline
            cand = _inline_candidate(curve, tick_id, kind, ticklabelpad,
                font, fonts, fontsize, format)
            cand === nothing || push!(candidates, (cand, true))
            continue
        end
        ixs = graticule_boundary_intersections(curve, boundary_px)
        if isempty(ixs) && kind === :parallel
            int_cand = _parallel_interior_candidate(curve, tick_id, side, center,
                ticklabelpad, rotation, alignment, font, fonts, fontsize, format)
            int_cand === nothing || push!(candidates, (int_cand, true))
            continue
        end
        for (px, comp, arc) in ixs
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
            ctangent = _curve_tangent_at(curve.projected_geometry, px)
            btangent = Point2d(0, 0)
            if 1 <= comp < length(boundary_px)
                b = boundary_px[comp + 1] .- boundary_px[comp]
                norm(b) > 1.0e-9 && (btangent = b ./ norm(b))
            end
            cand = label_candidate(tick_id, Point2d(pos...), text, nfont,
                fontsize, rotation, align, comp, arc; side = _label_side(n),
                tangent = ctangent, boundary_tangent = btangent,
                preferred_side = side)
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
    if quality === :interactive
        # Interactive frames: deduplicate but skip full overlap optimisation so
        # the camera can update promptly; final placement runs once interaction
        # settles.
        seen = Set{Int}()
        accepted = LabelCandidate[]
        for cand in chosen
            (cand.tick_id in seen && !allow_duplicates) && continue
            push!(accepted, cand)
            push!(seen, cand.tick_id)
        end
        return accepted
    end
    accepted = LabelCandidate[]
    seen = Set{Int}()
    rejected = LabelCandidate[]
    for cand in chosen
        (cand.tick_id in seen && !allow_duplicates) && continue
        if !_candidate_overlaps(cand, accepted)
            push!(accepted, cand)
            push!(seen, cand.tick_id)
        else
            push!(rejected, cand)
        end
    end
    _local_improve!(accepted, rejected)
    return accepted
end

function _candidate_overlaps(cand::LabelCandidate, accepted::Vector{LabelCandidate})
    return any(accepted) do a
        xoverlap = max(0.0,
            min(a.bbox_px.origin[1] + a.bbox_px.widths[1], cand.bbox_px.origin[1] + cand.bbox_px.widths[1]) -
            max(a.bbox_px.origin[1], cand.bbox_px.origin[1]))
        yoverlap = max(0.0,
            min(a.bbox_px.origin[2] + a.bbox_px.widths[2], cand.bbox_px.origin[2] + cand.bbox_px.widths[2]) -
            max(a.bbox_px.origin[2], cand.bbox_px.origin[2]))
        xoverlap > 2.0 && yoverlap > 2.0
    end
end

function _shift_candidate(cand::LabelCandidate, delta::Point2d)
    return LabelCandidate(
        cand.tick_id, cand.position_px .+ delta, cand.rotation, cand.alignment,
        Rect2d(Vec2d(cand.bbox_px.origin .+ Vec2d(delta[1], delta[2])), widths(cand.bbox_px)),
        cand.boundary_component, cand.boundary_arclength, cand.score, cand.text,
        cand.interior, cand.side, cand.tangent, cand.boundary_tangent,
        cand.preferred_side, cand.placement_class)
end

# Deterministic local improvement: try shifting rejected labels a few label
# widths along the boundary tangent so more of them can be kept.
function _local_improve!(accepted::Vector{LabelCandidate}, rejected::Vector{LabelCandidate})
    for cand in rejected
        norm(cand.boundary_tangent) < 0.5 && continue
        t = cand.boundary_tangent
        w = cand.bbox_px.widths[1]
        placed = false
        for dir in (1, -1), k in 1:3
            shifted = _shift_candidate(cand, t .* (dir * k * (w + 4.0)))
            if !_candidate_overlaps(shifted, accepted)
                push!(accepted, shifted)
                placed = true
                break
            end
        end
        placed && continue
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
