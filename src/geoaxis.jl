#=
# GeoAxis
=#

# Do lon = -180° and lon = +180° project to the same curve under `gridproj`? They are one physical
# meridian: pseudocylindrical/interrupted frames place them on opposite map edges (distinct), while
# oblique/azimuthal frames drawn with the full transform collapse them onto each other (the forward
# is 360°-periodic). Sampled at the first visible latitude where both project finite.
function _antimeridian_coincides(gridproj, ylo, yhi)
    for φ in (35.0, -35.0, 55.0, -55.0, 10.0)
        (φ < ylo || φ > yhi) && continue
        a = gridproj(-180.0, φ); b = gridproj(180.0, φ)
        (all(isfinite, a) && all(isfinite, b)) || continue
        return hypot(a[1] - b[1], a[2] - b[2]) < 1.0    # coincident to < 1 m ⇒ the same curve
    end
    return false
end

Makie.@Block GeoAxis <: Makie.AbstractAxis begin
    scene::Scene
    targetlimits::Observable{Rect2d}
    finallimits::Observable{Rect2d}
    xaxislinks::Vector{GeoAxis}
    yaxislinks::Vector{GeoAxis}
    block_limit_linking::Ref{Bool}
    suppress_projected_propagation::Ref{Bool}
    linked_geographic_limits::Observable{Union{Nothing, GeographicLimits}}
    cache::AxisCache
    interaction_active::Observable{Bool}
    mouseeventhandle::Makie.MouseEventHandle
    scrollevents::Observable{Makie.ScrollEvent}
    keysevents::Observable{Makie.KeysEvent}
    interactions::Dict{Symbol, Tuple{Bool, Any}}
    elements::Dict{Symbol, Any}
    transform_func::Observable{Any}
    inv_transform_func::Observable{Any}
    @attributes begin
        # unused - only for compat with Makie AbstractAxis functions
        xscale = identity
        yscale = identity
        # Layout observables for Block
        "The horizontal alignment of the block in its suggested bounding box."
        halign = :center
        "The vertical alignment of the block in its suggested bounding box."
        valign = :center
        "The width setting of the block."
        width = Makie.Auto()
        "The height setting of the block."
        height = Makie.Auto()
        "Controls if the parent layout can adjust to this block's width"
        tellwidth::Bool = true
        "Controls if the parent layout can adjust to this block's height"
        tellheight::Bool = true
        "The align mode of the block in its parent GridLayout."
        alignmode = Makie.Inside()

        # Projection
        "Projection of the source data. This is the value plots will default to, but can be overwritten via `plot(...; source=...)`"
        source = "+proj=longlat +datum=WGS84"
        "Projection that the axis uses to display the data."
        dest = "+proj=eqearth"

        "Controls if the y axis goes upwards (false) or downwards (true)"
        yreversed::Bool = false
        "Controls if the x axis goes rightwards (false) or leftwards (true)"
        xreversed::Bool = false
        "The relative margins added to the autolimits in x direction."
        xautolimitmargin::Tuple{Float64,Float64} = (0.05f0, 0.05f0)
        "The relative margins added to the autolimits in y direction."
        yautolimitmargin::Tuple{Float64,Float64} = (0.05f0, 0.05f0)
        "The limits that the user has manually set. They are reinstated when calling `reset_limits!` and are set to nothing by `autolimits!`. Can be either a tuple (xlow, xhigh, ylow, high) or a tuple (nothing_or_xlims, nothing_or_ylims). Are set by `xlims!`, `ylims!` and `limits!`."
        limits = (nothing, nothing)
        "The forced aspect ratio of the axis. `nothing` leaves the axis unconstrained, `DataAspect()` forces the same ratio as the ratio in data limits between x and y axis, `AxisAspect(ratio)` sets a manual ratio."
        aspect = Makie.DataAspect()
        autolimitaspect = nothing

        # appearance controls
        "The set of fonts which text in the axis should use.s"
        fonts = (; regular = "TeX Gyre Heros Makie")
        "The axis title string."
        title = ""
        "The font family of the title."
        titlefont = :bold
        "The title's font size."
        titlesize::Float64 = @inherit(:fontsize, 16f0)
        "The gap between axis and title."
        titlegap::Float64 = 4f0
        "Controls if the title is visible."
        titlevisible::Bool = true
        "The horizontal alignment of the title."
        titlealign::Symbol = :center
        "The color of the title"
        titlecolor::RGBAf = @inherit(:textcolor, :black)
        "The axis title line height multiplier."
        titlelineheight::Float64 = 1
        "The axis subtitle string."
        subtitle = ""
        "The font family of the subtitle."
        subtitlefont = :regular
        "The subtitle's font size."
        subtitlesize::Float64 = @inherit(:fontsize, 16f0)
        "The gap between subtitle and title."
        subtitlegap::Float64 = 0
        "Controls if the subtitle is visible."
        subtitlevisible::Bool = true
        "The color of the subtitle"
        subtitlecolor::RGBAf = @inherit(:textcolor, :black)
        "The axis subtitle line height multiplier."
        subtitlelineheight::Float64 = 1


        "The xlabel string."
        xlabel = ""
        "The ylabel string."
        ylabel = ""
        "The font family of the xlabel."
        xlabelfont = :regular
        "The font family of the ylabel."
        ylabelfont = :regular
        "The color of the xlabel."
        xlabelcolor::RGBAf = @inherit(:textcolor, :black)
        "The color of the ylabel."
        ylabelcolor::RGBAf = @inherit(:textcolor, :black)
        "The font size of the xlabel."
        xlabelsize::Float64 = @inherit(:fontsize, 16f0)
        "The font size of the ylabel."
        ylabelsize::Float64 = @inherit(:fontsize, 16f0)
        "Controls if the xlabel is visible."
        xlabelvisible::Bool = true
        "Controls if the ylabel is visible."
        ylabelvisible::Bool = true
        "The padding between the xlabel and the ticks or axis."
        xlabelpadding::Float64 = 3f0
        "The padding between the ylabel and the ticks or axis."
        ylabelpadding::Float64 = 5f0 # xlabels usually have some more visual padding because of ascenders, which are larger than the hadvance gaps of ylabels
        "The xlabel rotation in radians."
        xlabelrotation = Makie.automatic
        "The ylabel rotation in radians."
        ylabelrotation = Makie.automatic

        "The x (longitude) ticks - can be a vector or a Makie tick finding algorithm."
        xticks = Makie.automatic
        "The y (latitude) ticks - can be a vector or a Makie tick finding algorithm."
        yticks = Makie.automatic

        "Format for x (longitude) ticks."
        xtickformat = Makie.automatic
        "Format for y (latitude) ticks."
        ytickformat = Makie.automatic
        "The font family of the xticklabels."
        xticklabelfont = :regular
        "The font family of the yticklabels."
        yticklabelfont = :regular
        "The color of xticklabels."
        xticklabelcolor::RGBAf = @inherit(:textcolor, :black)
        "The color of yticklabels."
        yticklabelcolor::RGBAf = @inherit(:textcolor, :black)
        "The font size of the xticklabels."
        xticklabelsize::Float64 = @inherit(:fontsize, 16f0)
        "The font size of the yticklabels."
        yticklabelsize::Float64 = @inherit(:fontsize, 16f0)
        "Controls if the xticklabels are visible."
        xticklabelsvisible::Bool = true
        "Controls if the yticklabels are visible."
        yticklabelsvisible::Bool = true
        "The space reserved for the xticklabels."
        xticklabelspace::Union{Makie.Automatic, Float64} = Makie.automatic
        "The space reserved for the yticklabels."
        yticklabelspace::Union{Makie.Automatic, Float64} = Makie.automatic
        "The space between xticks and xticklabels."
        xticklabelpad::Float64 = 5f0
        "The space between yticks and yticklabels."
        yticklabelpad::Float64 = 5f0
        "The counterclockwise rotation of the xticklabels in radians."
        xticklabelrotation::Float64 = 0f0
        "The counterclockwise rotation of the yticklabels in radians."
        yticklabelrotation::Float64 = 0f0
        "The horizontal and vertical alignment of the xticklabels."
        xticklabelalign::Union{Makie.Automatic, Tuple{Symbol, Symbol}} = Makie.automatic
        "The horizontal and vertical alignment of the yticklabels."
        yticklabelalign::Union{Makie.Automatic, Tuple{Symbol, Symbol}} = Makie.automatic
        "The size of the xtick marks."
        xticksize::Float64 = 6f0
        "The size of the ytick marks."
        yticksize::Float64 = 6f0
        "Controls if the xtick marks are visible."
        xticksvisible::Bool = true
        "Controls if the ytick marks are visible."
        yticksvisible::Bool = true
        "The alignment of the xtick marks relative to the axis spine (0 = out, 1 = in)."
        xtickalign::Float64 = 0f0
        "The alignment of the ytick marks relative to the axis spine (0 = out, 1 = in)."
        ytickalign::Float64 = 0f0
        "The width of the xtick marks."
        xtickwidth::Float64 = 1f0
        "The width of the ytick marks."
        ytickwidth::Float64 = 1f0
        "The color of the xtick marks."
        xtickcolor::RGBAf = RGBf(0, 0, 0)
        "The color of the ytick marks."
        ytickcolor::RGBAf = RGBf(0, 0, 0)
        # "The width of the axis spines."
        # spinewidth::Float64 = 1f0
        "Controls if the x grid lines are visible."
        xgridvisible::Bool = true
        "Controls if the y grid lines are visible."
        ygridvisible::Bool = true
        "The width of the x grid lines."
        xgridwidth::Float64 = 1f0
        "The width of the y grid lines."
        ygridwidth::Float64 = 1f0
        "The color of the x grid lines."
        xgridcolor::RGBAf = RGBAf(0, 0, 0, 0.12)   # match Makie's default Axis gridline
        "The color of the y grid lines."
        ygridcolor::RGBAf = RGBAf(0.0, 0, 0, 0.12)
        "The linestyle of the x grid lines."
        xgridstyle = nothing
        "The linestyle of the y grid lines."
        ygridstyle = nothing
        "Controls if minor ticks on the x axis are visible"
        xminorticksvisible::Bool = false
        "The alignment of x minor ticks on the axis spine"
        xminortickalign::Float64 = 0f0
        "The tick size of x minor ticks"
        xminorticksize::Float64 = 4f0
        "The tick width of x minor ticks"
        xminortickwidth::Float64 = 1f0
        "The tick color of x minor ticks"
        xminortickcolor::RGBAf = :black
        "The tick locator for the x minor ticks"
        xminorticks = IntervalsBetween(2)
        "Controls if minor ticks on the y axis are visible"
        yminorticksvisible::Bool = false
        "The alignment of y minor ticks on the axis spine"
        yminortickalign::Float64 = 0f0
        "The tick size of y minor ticks"
        yminorticksize::Float64 = 4f0
        "The tick width of y minor ticks"
        yminortickwidth::Float64 = 1f0
        "The tick color of y minor ticks"
        yminortickcolor::RGBAf = :black
        "The tick locator for the y minor ticks"
        yminorticks = IntervalsBetween(2)
        "Controls if the x minor grid lines are visible."
        xminorgridvisible::Bool = false
        "Controls if the y minor grid lines are visible."
        yminorgridvisible::Bool = false
        "The width of the x minor grid lines."
        xminorgridwidth::Float64 = 1f0
        "The width of the y minor grid lines."
        yminorgridwidth::Float64 = 1f0
        "The color of the x minor grid lines."
        xminorgridcolor::RGBAf = RGBAf(0, 0, 0, 0.05)
        "The color of the y minor grid lines."
        yminorgridcolor::RGBAf = RGBAf(0, 0, 0, 0.05)
        "The linestyle of the x minor grid lines."
        xminorgridstyle = nothing
        "The linestyle of the y minor grid lines."
        yminorgridstyle = nothing
        "Controls if the projection-boundary spine is visible."
        spinevisible::Bool = true
        "The width of the projection-boundary spine."
        spinewidth::Float64 = 1f0
        "The color of the projection-boundary spine."
        spinecolor::RGBAf = RGBAf(0, 0, 0, 1)   # match Makie's default Axis spine
        "The button for panning."
        panbutton::Makie.Mouse.Button = Makie.Mouse.right
        "The key for limiting panning to the x direction."
        xpankey::Makie.Keyboard.Button = Makie.Keyboard.x
        "The key for limiting panning to the y direction."
        ypankey::Makie.Keyboard.Button = Makie.Keyboard.y
        "The key for limiting zooming to the x direction."
        xzoomkey::Makie.Keyboard.Button = Makie.Keyboard.x
        "The key for limiting zooming to the y direction."
        yzoomkey::Makie.Keyboard.Button = Makie.Keyboard.y

        "Locks interactive panning in the x direction."
        xpanlock::Bool = false
        "Locks interactive panning in the y direction."
        ypanlock::Bool = false
        "Locks interactive zooming in the x direction."
        xzoomlock::Bool = false
        "Locks interactive zooming in the y direction."
        yzoomlock::Bool = false
        "Controls if rectangle zooming affects the x dimension."
        xrectzoom::Bool = true
        "Controls if rectangle zooming affects the y dimension."
        yrectzoom::Bool = true

        xaxisposition::Symbol = :bottom
        yaxisposition::Symbol = :left

    end
end

# Makie generic object API
Makie.transform_func(ax::GeoAxis) = ax.transform_func[]

# Spines

const SpinePoint = NamedTuple{(:input, :projected, :dir, :intersect_dir),Tuple{Point2d,Point2d,Point2d,Point2d}}

struct Spines
    top::Vector{SpinePoint}
    bottom::Vector{SpinePoint}
    left::Vector{SpinePoint}
    right::Vector{SpinePoint}
end

Spines() = Spines(SpinePoint[], SpinePoint[], SpinePoint[], SpinePoint[])

function interset_rect(rect::Rect2, line_start::Point2, line_end::Point2)
    mini, maxi = extrema(rect)
    line = Line(line_start, line_end)

    # Bottom Side
    side = Line(Point2{Float64}(mini[1], mini[2]), Point2{Float64}(maxi[1], mini[2]))
    intersected, p = intersects(side, line)
    intersected && return p, side

    # Right side
    side = Line(Point2{Float64}(maxi[1], mini[2]), Point2{Float64}(maxi[1], maxi[2]))
    intersected, p = intersects(side, line)
    intersected && return p, side

    # Top side
    side = Line(Point2{Float64}(maxi[1], maxi[2]), Point2{Float64}(mini[1], maxi[2]))
    intersected, p = intersects(side, line)
    intersected && return p, side

    # Left side
    side = Line(Point2{Float64}(mini[1], maxi[2]), Point2{Float64}(mini[1], mini[2]))
    intersected, p = intersects(side, line)
    intersected && return p, side
    return nothing, nothing
end

function valid_line_in_limits(trans, trans_rev, rect, point_start, point_stop, n=100)
    xrange = LinRange(point_start[1], point_stop[1], n)
    yrange = LinRange(point_start[2], point_stop[2], n)
    lines = Vector{Point2d}[]
    lines_t = Vector{Point2d}[]

    # With non linear transforms, we need to check points inbetween for intersections
    # So we transform all points first and filter out non finite results
    was_finite = false
    for i in 1:n
        point = Point2d(xrange[i], yrange[i])
        point_t = Makie.apply_transform(trans, point)
        if isfinite(point_t)
            if !was_finite
                push!(lines, Point2d[])
                push!(lines_t, Point2d[])
            end
            push!(lines[end], point)
            push!(lines_t[end], point_t)
            was_finite = true
        else
            was_finite = false
        end
    end

    lines_inside = Vector{Point2d}[]
    lines_inside_t = Vector{Point2d}[]
    lines_inside_t = Vector{Point2d}[]
    intersections = Vector{Union{Line{2,Float64},Nothing}}[]
    for (points, points_t) in zip(lines, lines_t)
        was_inside = false

        for (a, b, a_t, b_t) in zip(points[1:end-1], points[2:end], points_t[1:end-1], points_t[2:end])
            a_in = a_t in rect
            b_in = b_t in rect
            if !was_inside && (a_in || b_in)
                push!(lines_inside, Point2d[])
                push!(lines_inside_t, Point2d[])
                push!(intersections, Union{Line{2,Float64},Nothing}[nothing, nothing])
            end
            if a_in && b_in
                was_inside = true
                push!(lines_inside[end], a)
                push!(lines_inside[end], b)

                push!(lines_inside_t[end], a_t)
                push!(lines_inside_t[end], b_t)
            elseif a_in
                had_points = isempty(lines_inside[end])
                push!(lines_inside[end], a)
                push!(lines_inside_t[end], a_t)
                p, iline = interset_rect(rect, a_t, b_t)
                if !isnothing(p)
                    if had_points
                        intersections[end][1] = iline
                    else
                        intersections[end][2] = iline
                    end
                    push!(lines_inside[end], Makie.apply_transform(trans_rev, p))
                    push!(lines_inside_t[end], p)
                end
                was_inside = false
            elseif b_in
                had_points = isempty(lines_inside[end])
                push!(lines_inside[end], b)
                push!(lines_inside_t[end], b_t)
                p, iline = interset_rect(rect, a_t, b_t)
                if !isnothing(p)
                    if had_points
                        intersections[end][1] = iline
                    else
                        intersections[end][2] = iline
                    end
                    push!(lines_inside[end], Makie.apply_transform(trans_rev, p))
                    push!(lines_inside_t[end], p)
                end
                was_inside = false
            else
                was_inside = false
            end
        end
    end
    return lines_inside, lines_inside_t, intersections
end

function add_to_lines!(result, valid_line, line_transformed, intersections, spine_start, spine_end, dim)
    idx = sortperm(valid_line, by=x -> x[dim == 1 ? 2 : 1])
    line_transformed = line_transformed[idx]
    valid_line = valid_line[idx]

    append!(result, line_transformed)
    push!(result, Point2d(NaN))

    # Add normal vector for ticks
    i_start, i_end = intersections

    if !isnothing(spine_start)
        v1_t, v2_t = line_transformed[1], line_transformed[2]
        dir = normalize(v1_t .- v2_t)
        if !isnothing(i_start)
            intersect_dir = i_start[1] .- i_start[2]
        else
            intersect_dir = Point2d(NaN)
        end
        push!(spine_start, (input=valid_line[1], projected=v1_t, dir=dir, intersect_dir=intersect_dir))
    end

    if !isnothing(spine_end)
        s_1_t, s_2_t = line_transformed[end], line_transformed[end-1]
        dir = normalize(s_1_t .- s_2_t)
        if !isnothing(i_end)
            intersect_dir = i_end[1] .- i_end[2]
        else
            intersect_dir = Point2d(NaN)
        end
        push!(spine_end, (input=valid_line[end], projected=s_1_t, dir=dir, intersect_dir=intersect_dir))
    end
end

function project_tick_points!(result, trans, trans_inverse, range, coordinate, dim, limit_rect, spine_start, spine_end)
    # dim == 1, is for longitude ticks

    point_fun(tick) = dim === 1 ? Point2(coordinate, tick) : Point2(tick, coordinate)

    start = point_fun(range[1])
    stop = point_fun(range[end])

    lines, lines_transformed, intersections = valid_line_in_limits(trans, trans_inverse, limit_rect, start, stop)
    spine_start_length = length(spine_start)
    spine_end_length = length(spine_end)
    for (line, line_t, intersect) in zip(lines, lines_transformed, intersections)
        length(line) < 2 && continue
        # Only add one start/end to spine
        _spine_start = spine_start_length == length(spine_start) ? spine_start : nothing
        _spine_end = spine_end_length == length(spine_end) ? spine_end : nothing
        add_to_lines!(result, line, line_t, intersect, _spine_start, _spine_end, dim)
    end
    return
end

function mean_distances(points)
    dists = Float64[]
    last_px = points[1].projected
    for px in @view points[2:end]
        push!(dists, norm(last_px .- px.projected))
        last_px = px.projected
    end
    return mean(dists)
end

# Choses the spine with the biggest mean distance between points
function choose_side(a, b)
    isempty(a) && return b
    isempty(b) && return a
    distsa = mean_distances(a)
    distsb = mean_distances(b)
    distsa - distsb < 3 && return a
    return distsb <= distsa ? a : b
end

function angle_between(v1::Point, v2::Point)
    dot_product = dot(v1, v2)
    norms = norm(v1) * norm(v2)
    angle = acos(dot_product / norms)
    return angle
end

function vis_spine!(points, text, points_px, d, mindist, labeloffset)
    last_point = nothing
    for p in points
        p_px = p.projected
        if !isnothing(last_point)
            dist = norm(last_point .- p_px)
            dist < mindist && continue
        else
            last_point = p_px
        end
        if norm(p.dir) < 0.1
            continue
        end
        !isfinite(p.input) && continue
        if isfinite(p.intersect_dir)
            line_dir = p.intersect_dir
            dir = normalize(Point2d(-line_dir[2], line_dir[1]))
        else
            dir = p.dir
        end
        last_point = p_px
        # TODO use xticklabelspace
        # TODO use xticklabelpad
        p_offset = p_px .+ (p.dir .* (3 * labeloffset))
        push!(points_px, p_offset)
		x = round(p.input[d]; sigdigits = 3)
        push!(text, string(isinteger(x) ? round(Int, x) : x, "°"))
    end
end

function filter_too_close(point, all_points)
    a = point.projected
    for p in all_points
        b = p.projected
        if norm(a .- b) < 30
            return false
        end
    end
    return true
end

function Makie.initialize_block!(axis::GeoAxis)

    # Set up transformations first, so that the scene can be set up
    # and linked to those.
    transform_obs = Observable{Any}(identity; ignore_equal_values=true)
    transform_inv_obs = Observable{Any}(identity; ignore_equal_values=true)
    transform_ticks_obs = Observable{Any}(identity; ignore_equal_values=true)
    transform_ticks_inv_obs = Observable{Any}(identity; ignore_equal_values=true)
    setfield!(axis, :transform_func, transform_obs)
    setfield!(axis, :inv_transform_func, transform_inv_obs)
    setfield!(axis, :xaxislinks, GeoAxis[])
    setfield!(axis, :yaxislinks, GeoAxis[])
    setfield!(axis, :block_limit_linking, Ref(false))
    setfield!(axis, :suppress_projected_propagation, Ref(false))
    setfield!(axis, :linked_geographic_limits,
        Observable{Union{Nothing, GeographicLimits}}(nothing; ignore_equal_values = true))
    setfield!(axis, :cache, AxisCache())
    setfield!(axis, :interaction_active, Observable(false; ignore_equal_values = true))

    # Set up the axis for the Scene, mostly using Makie's existing functionality
    scene = axis_setup!(axis)

    # Shorthand for what you see below - ONLY ACCESSIBLE WITHIN THIS FUNCTION!!
    Obs(x) = Observable(x; ignore_equal_values=true)

    # Keep the transformations up to date.
    onany(scene, axis.dest, axis.source; update=true) do tp, sp
        # First we perform the transformation for the axis,
        trans = create_transform(tp, sp)
        transform_obs[] = trans
        transform_inv_obs[] = Makie.inverse_transform(trans)
        # and next for the ticks - this assumes an input CRS in
        # PROJ-string format, which is not necessarily the case, but suffices for now.
        # What this should do, is check using Proj whether the input CRS is equivalent
        # to EPSG 4326, which is actually quite doable - especially using a cache of some kind.
        # What this is actually doing, is creating a transformation that takes the input CRS
        # and transforms it to the WGS84 CRS, which is how we display the ticks.
        # If you wanted ticks in the input CRS, you'd have to wait until a generic `NonlinearAxis`
        # is implemented, which would then not have any special treatment for geographic stuff.
        if sp == "+proj=longlat +datum=WGS84" || sp == "+proj=latlong +datum=WGS84 +type=crs" || sp == GeoFormatTypes.EPSG(4326)
            transform_ticks_obs[] = trans
            transform_ticks_inv_obs[] = transform_inv_obs[]
        else
            transform_ticks_obs[] = create_transform(tp, "+proj=longlat +datum=WGS84")
            transform_ticks_inv_obs[] = create_transform("+proj=longlat +datum=WGS84", tp)
        end
    end


    lonticks_line_obs = Obs(Point2d[])
    latticks_line_obs = Obs(Point2d[])

    spines_obs = Obs(Spines())
    graticule_obs = Obs(GraticuleCurve[])
    viewport_obs = Obs(GeoViewport())
    ticks_obs = Obs((Float64[], Float64[]))
    finallimits = map(identity, scene, axis.finallimits; ignore_equal_values=true)
    # Quantise viewport changes so sub-pixel layout feedback cannot keep the
    # graticule/label pipeline running indefinitely.
    vp_unchanged = map(_quantized_rect, scene, scene.viewport; ignore_equal_values=true)
    # This is kind of the main redrawing loop for the axis.  This should really be
    # factored out into a sync and async function, so that zooming is fluid, but
    # we can figure that out later.
    # What this does is first calculate limits and ticks, then create spines and
    # project them.  Those are stored in Observables which are used to produce
    # lineplots later on that form the grid.
    # TODO: implement a minor grid.
    onany(scene, axis.xticks, axis.yticks, transform_ticks_obs, finallimits, vp_unchanged,
        axis.interaction_active;
        update=true) do user_xticks, user_yticks, trans, fl, vp, interactive
        quality_scale = interactive ? 0.25 : 1.0

        lon_transformed = Point2d[]
        lat_transformed = Point2d[]
        limit_rect = Makie.to_value(axis.finallimits)
        trans_inverse = Makie.to_value(transform_ticks_inv_obs)

        limits_t = Makie.apply_transform(trans_inverse, limit_rect)
        xlims = Makie.xlimits(limits_t)
        ylims = Makie.ylimits(limits_t)

        xticks = user_xticks isa Makie.Automatic ? geoticks(-180, 180, xlims...) : Makie.get_tickvalues(user_xticks, xlims...)
        yticks = user_yticks isa Makie.Automatic ? geoticks(-90, 90, ylims...) : Makie.get_tickvalues(user_yticks, ylims...)

        spines = spines_obs[]
        foreach(empty!, [spines.left, spines.right, spines.bottom, spines.top])

        # Grid line geometry goes through the same sphere-clip dispatch as everything else, so
        # meridians/parallels break at the projection's discontinuity instead of smearing across
        # it (antimeridian uses the centred frame, Option B). project_tick_points! is still used
        # for the spine/tick-mark anchors at the limit-rect edges.
        clip = clip_strategy(trans)
        rotated = clip isa AntimeridianClip
        gridproj = _projector(rotated ?
            create_transform(_centred_dest(to_value(axis.dest)), "+proj=longlat +datum=WGS84") : trans)
        gridscale = resample_scale(gridproj) * quality_scale

        # The antimeridian is one physical meridian, but it appears as a tick at both -180° and
        # +180°. Pseudocylindrical/interrupted frames map those to distinct map edges (draw both);
        # oblique/azimuthal frames drawn with the full transform map them to the SAME curve
        # (`f(-180)≡f(180)`, e.g. bertin/aeqd/spilhaus), where drawing both overdraws the seam. Drop
        # the +180° duplicate only when it actually coincides with -180° (sampled at a visible lat).
        skip180 = let lo = yticks[1], hi = yticks[end]
            any(t -> isapprox(t, -180.0; atol = 1.0e-6), xticks) &&
                any(t -> isapprox(t, 180.0; atol = 1.0e-6), xticks) &&
                _antimeridian_coincides(gridproj, lo, hi)
        end
        xticks_draw = skip180 ?
            filter(t -> !isapprox(t, 180.0; atol = 1.0e-6), xticks) : xticks

        # Tick-mark anchors at the visible limit-rect edges.
        for lon in xticks_draw
            range = LinRange(yticks[1], yticks[end], 100)
            project_tick_points!(Point2d[], trans, trans_inverse, range, lon, 1, limit_rect, spines.bottom, spines.top)
        end
        for lat in yticks
            range = LinRange(xticks[1], xticks[end], 100)
            project_tick_points!(Point2d[], trans, trans_inverse, range, lat, 2, limit_rect, spines.left, spines.right)
        end

        # Adaptive graticule geometry through the shared sphere-clip pipeline.
        gp = geoprojection(to_value(axis.dest), to_value(axis.source))
        extent = (Float64(xlims[1]), Float64(xlims[2]), Float64(ylims[1]), Float64(ylims[2]))
        gkey = (to_value(axis.dest), to_value(axis.source), extent,
            length(xticks_draw), length(yticks), quality_scale)
        curves = getcache!(axis.cache.graticules, gkey, () ->
            generate_graticule(gp, xticks_draw, yticks, extent;
                project = gridproj, scale = gridscale, rotated = rotated))
        for c in curves
            target = c.kind === :meridian ? lon_transformed : lat_transformed
            append!(target, c.projected_geometry)
            push!(target, Point2d(NaN, NaN))
        end

        lonticks_line_obs[] = lon_transformed
        latticks_line_obs[] = lat_transformed
        graticule_obs[] = curves
        ticks_obs[] = (Float64.(xticks_draw), Float64.(yticks))
        bkey = (to_value(axis.dest), to_value(axis.source))
        boundary = getcache!(axis.cache.boundary, bkey, () ->
            try
                boundary_points(to_value(axis.dest), to_value(axis.source))
            catch
                Point2d[]
            end)
        update_geoviewport!(viewport_obs, gp, limit_rect, boundary)
        notify(spines_obs)
        return
    end
    # These are the grid plots from earlier.
    longridplot = lines!(scene, lonticks_line_obs; color=axis.xgridcolor, linewidth=axis.xgridwidth,
        visible=axis.xgridvisible, linestyle=axis.xgridstyle, transparency=true, inspectable=false)
    translate!(longridplot, 0, 0, 100)
    latgridplot = lines!(scene, latticks_line_obs; color=axis.ygridcolor, linewidth=axis.ygridwidth,
        visible=axis.ygridvisible, linestyle=axis.ygridstyle, transparency=true, inspectable=false)
    translate!(latgridplot, 0, 0, 100)

    # Projection-domain outline (the d3 `.sphere()` boundary of the active clip), drawn as the
    # axis spine: limb circle for azimuthal horizons, ellipse/rectangle for cylindricals.
    boundary_obs = lift(axis.dest, axis.source) do dest, src
        getcache!(axis.cache.boundary, (dest, src), () ->
            try
                boundary_points(dest, src)
            catch
                Point2d[]
            end)
    end
    spineplot = lines!(scene, boundary_obs; color=axis.spinecolor, linewidth=axis.spinewidth,
        visible=axis.spinevisible, transparency=true, inspectable=false)
    translate!(spineplot, 0, 0, 100)

    # This creates the spines and ticklabels plots for the grid.
    cam = scene.camera
    lon_spine = Obs(SpinePoint[])
    lat_spine = Obs(SpinePoint[])
    lon_labels = Obs(LabelCandidate[])
    lat_labels = Obs(LabelCandidate[])
    lon_text = Obs(String[])
    lon_points_px = Obs(Point2d[])
    lon_align = Obs(Tuple{Symbol, Symbol}[])
    lon_rotation = Obs(Float64[])
    lat_text = Obs(String[])
    lat_points_px = Obs(Point2d[])
    lat_align = Obs(Tuple{Symbol, Symbol}[])
    lat_rotation = Obs(Float64[])
    lon_tick_segments_obs = Obs(Point2d[])
    lat_tick_segments_obs = Obs(Point2d[])
    decoration_extents = Obs(DecorationExtents())
    prev_decoration_extents = Ref(DecorationExtents())
    xlabel_pos_obs = Obs(Point2d(0, 0))
    ylabel_pos_obs = Obs(Point2d(0, 0))

    # The spine/tick-label positions feed the axis protrusions, which feed the layout, which
    # changes `cam.projectionview`, re-triggering this very callback *synchronously* on the same
    # stack. For most projections that settles in 1–2 passes, but some full-disk azimuthal aspects
    # (e.g. equatorial `+proj=laea`) never converge and recurse until the stack overflows. Cap the
    # synchronous re-entry depth: converging projections never approach the cap, while a runaway is
    # bounded to a finite (near-settled) result instead of crashing.
    spine_reentry = Ref(0)
    onany(scene, spines_obs, graticule_obs, boundary_obs, cam.projectionview, vp_unchanged,
        axis.xticksvisible, axis.yticksvisible,
        axis.xticklabelsvisible, axis.yticklabelsvisible,
        axis.xlabelvisible, axis.ylabelvisible, axis.xlabel, axis.ylabel,
        axis.xticklabelpad, axis.yticklabelpad, axis.xticksize, axis.yticksize,
        axis.xtickalign, axis.ytickalign, axis.xticklabelfont, axis.yticklabelfont,
        axis.xticklabelsize, axis.yticklabelsize) do spines, curves, boundary, pv, area, rest...
        spine_reentry[] >= 8 && return
        spine_reentry[] += 1
        try
            poffset = minimum(area)
            vp = Rect2d(Vec2d(minimum(area)), Vec2d(widths(area)))
            project_px(p) = to_ndim(Point2d, Makie.project(cam, :data, :pixel, p), 0.0f0) .+ poffset
            project_p(p) = (input=p.input, projected=project_px(p.projected), dir=p.dir, intersect_dir=p.intersect_dir)

            left = project_p.(spines.left)
            right = project_p.(spines.right)
            bottom = project_p.(spines.bottom)
            top = project_p.(spines.top)

            lonspine = choose_side(left, right)
            latspine = choose_side(bottom, top)

            # Filter out ticks that go almost parallel to boundingbox
            function too_narrow(p)
                if isfinite(p.intersect_dir)
                    line_dir = p.intersect_dir
                    a = abs(angle_between(p.dir, line_dir))
                    (a < 0.2 || abs(pi - a) < 0.2) && return false
                end
                return true
            end

            filter!(too_narrow, lonspine)
            filter!(too_narrow, latspine)

            filter!(p -> filter_too_close(p, latspine), lonspine)
            filter!(p -> filter_too_close(p, lonspine), latspine)
            lon_spine[] = lonspine
            lat_spine[] = latspine

            # Boundary-aware labels from the actual visible projection boundary.
            fonts = theme(axis.blockscene, :fonts)
            cxp0 = vp.origin[1] + vp.widths[1] / 2
            cyp0 = vp.origin[2] + vp.widths[2] / 2
            boundary_px = filter(
                p -> isfinite(p[1]) && isfinite(p[2]) &&
                    abs(p[1] - cxp0) < 1.0e5 && abs(p[2] - cyp0) < 1.0e5,
                project_px.(boundary))
            xt, yt = ticks_obs[]
            meridian_curves = project_curves_px(
                [c for c in curves if c.kind === :meridian], project_px)
            parallel_curves = project_curves_px(
                [c for c in curves if c.kind === :parallel], project_px)

            quality = axis.interaction_active[] ? :interactive : :final
            vpw = vp.widths[1] ÷ 8
            vph = vp.widths[2] ÷ 8
            lkey = (
                to_value(axis.dest), to_value(axis.source),
                xt, yt, Int(vpw), Int(vph), quality,
                axis.xaxisposition[], axis.yaxisposition[],
                (Float64(axis.xticklabelpad[]), Float64(axis.yticklabelpad[]),
                    Float64(axis.xticksize[]), Float64(axis.yticksize[]),
                    Float64(axis.xtickalign[]), Float64(axis.ytickalign[]),
                    Float64(axis.xticklabelsize[]), Float64(axis.yticklabelsize[])),
            )
            lon_cands = getcache!(axis.cache.labels, (lkey..., :meridian), () ->
                place_graticule_labels(meridian_curves, xt, :meridian, boundary_px;
                    side = axis.xaxisposition[], ticklabelpad = axis.xticklabelpad[],
                    ticksize = axis.xticksize[], tickalign = axis.xtickalign[],
                    rotation = axis.xticklabelrotation[], alignment = axis.xticklabelalign[],
                    font = axis.xticklabelfont[], fonts = fonts,
                    fontsize = axis.xticklabelsize[], format = axis.xtickformat[],
                    quality = quality))
            lat_cands = getcache!(axis.cache.labels, (lkey..., :parallel), () ->
                place_graticule_labels(parallel_curves, yt, :parallel, boundary_px;
                    side = axis.yaxisposition[], ticklabelpad = axis.yticklabelpad[],
                    ticksize = axis.yticksize[], tickalign = axis.ytickalign[],
                    rotation = axis.yticklabelrotation[], alignment = axis.yticklabelalign[],
                    font = axis.yticklabelfont[], fonts = fonts,
                    fontsize = axis.yticklabelsize[], format = axis.ytickformat[],
                    quality = quality))

            lon_labels[] = lon_cands
            lat_labels[] = lat_cands
            lon_pts, lon_strs, lon_als, lon_rots = renderable_label_data(lon_cands)
            lat_pts, lat_strs, lat_als, lat_rots = renderable_label_data(lat_cands)
            lon_points_px[] = lon_pts; lon_text[] = lon_strs
            lon_align[] = lon_als; lon_rotation[] = lon_rots
            lat_points_px[] = lat_pts; lat_text[] = lat_strs
            lat_align[] = lat_als; lat_rotation[] = lat_rots

            # Actual tick marks (pixel segments).
            lon_tick_segments_obs[] = tick_segments(lonspine, vp, axis.yticksize[], axis.ytickalign[])
            lat_tick_segments_obs[] = tick_segments(latspine, vp, axis.xticksize[], axis.xtickalign[])

            # Viewport-independent protrusion extents: tick length + label padding +
            # measured text size. They do NOT depend on the viewport, so the
            # label -> protrusion -> layout loop converges.
            ext = DecorationExtents()
            cxp = vp.origin[1] + vp.widths[1] / 2
            cyp = vp.origin[2] + vp.widths[2] / 2
            xtick_out = axis.xticksize[] * (1.0 - axis.xtickalign[])
            ytick_out = axis.yticksize[] * (1.0 - axis.ytickalign[])
            if axis.xticksvisible[]
                for p in latspine
                    n = _spine_outward_normal(p, Point2d(cxp, cyp))
                    side = abs(n[1]) >= abs(n[2]) ?
                        (n[1] < 0 ? :left : :right) :
                        (n[2] < 0 ? :bottom : :top)
                    add_extent!(ext, side, xtick_out)
                end
            end
            if axis.yticksvisible[]
                for p in lonspine
                    n = _spine_outward_normal(p, Point2d(cxp, cyp))
                    side = abs(n[1]) >= abs(n[2]) ?
                        (n[1] < 0 ? :left : :right) :
                        (n[2] < 0 ? :bottom : :top)
                    add_extent!(ext, side, ytick_out)
                end
            end
            if axis.xticklabelsvisible[]
                for cand in lon_cands
                    cand.interior && continue
                    off = xtick_out + axis.xticklabelpad[] + widths(cand.bbox_px)[2]
                    add_extent!(ext, cand.side, off)
                end
            end
            if axis.yticklabelsvisible[]
                for cand in lat_cands
                    cand.interior && continue   # interior labels reserve no layout space
                    off = ytick_out + axis.yticklabelpad[] + widths(cand.bbox_px)[1]
                    add_extent!(ext, cand.side, off)
                end
            end
            # Axis labels reserve space only when visible and non-empty.
            xlbl = axis.xlabel[]
            if !Makie.iswhitespace(xlbl) && axis.xlabelvisible[]
                xbb = _text_bbox(xlbl, axis.xlabelfont[], fonts, axis.xlabelsize[])
                xh = widths(xbb)[2]
                bottom_prot = ext.bottom
                xpos = Point2d(cxp, vp.origin[2] - bottom_prot - axis.xlabelpadding[] - xh / 2)
                xlabel_pos_obs[] = xpos
                add_extent!(ext, :bottom, axis.xlabelpadding[] + xh)
            end
            ylbl = axis.ylabel[]
            if !Makie.iswhitespace(ylbl) && axis.ylabelvisible[]
                ybb = _text_bbox(ylbl, axis.ylabelfont[], fonts, axis.ylabelsize[])
                yw = widths(ybb)[2]; yh = widths(ybb)[1]   # rotated -π/2: width/height swap
                left_prot = ext.left
                ypos = Point2d(vp.origin[1] - left_prot - axis.ylabelpadding[] - yw / 2, cyp)
                ylabel_pos_obs[] = ypos
                add_extent!(ext, :left, axis.ylabelpadding[] + yw)
            end
            # Only publish when the extents materially changed; this is what lets the
            # label -> protrusion -> viewport -> label loop converge instead of
            # oscillating forever on sub-pixel differences.
            if !same_extents(prev_decoration_extents[], ext)
                prev_decoration_extents[] =
                    DecorationExtents(ext.left, ext.right, ext.bottom, ext.top)
                decoration_extents[] = ext
            end
            return
        finally
            spine_reentry[] -= 1
        end
    end

    lattex = text!(axis.blockscene, lat_points_px;
        text = lat_text,
        space = :pixel,
        align = lat_align,
        rotation = lat_rotation,
        font = axis.xticklabelfont,
        color = axis.xticklabelcolor,
        fontsize = axis.xticklabelsize,
        visible = axis.xticklabelsvisible,
    )

    lontex = text!(axis.blockscene, lon_points_px;
        text = lon_text,
        space = :pixel,
        align = lon_align,
        rotation = lon_rotation,
        font = axis.yticklabelfont,
        color = axis.yticklabelcolor,
        fontsize = axis.yticklabelsize,
        visible = axis.yticklabelsvisible,
    )

    lon_ticks_plot = linesegments!(axis.blockscene, lon_tick_segments_obs;
        space = :pixel, color = axis.ytickcolor, linewidth = axis.ytickwidth,
        visible = axis.yticksvisible, inspectable = false)
    lat_ticks_plot = linesegments!(axis.blockscene, lat_tick_segments_obs;
        space = :pixel, color = axis.xtickcolor, linewidth = axis.xtickwidth,
        visible = axis.xticksvisible, inspectable = false)

    xlabeltext = text!(axis.blockscene, xlabel_pos_obs;
        text = axis.xlabel, space = :pixel, align = (:center, :center),
        font = axis.xlabelfont, color = axis.xlabelcolor, fontsize = axis.xlabelsize,
        visible = axis.xlabelvisible, inspectable = false)
    ylabeltext = text!(axis.blockscene, ylabel_pos_obs;
        text = axis.ylabel, space = :pixel, align = (:center, :center),
        rotation = -π / 2, font = axis.ylabelfont, color = axis.ylabelcolor,
        fontsize = axis.ylabelsize, visible = axis.ylabelvisible, inspectable = false)

    fonts = theme(axis.blockscene, :fonts)

    elements = Dict{Symbol,Any}()
    setfield!(axis, :elements, elements)
    elements[:xgrid] = longridplot
    elements[:ygrid] = latgridplot
    elements[:xticklabels] = lontex
    elements[:yticklabels] = lattex
    elements[:xticks] = lon_ticks_plot
    elements[:yticks] = lat_ticks_plot
    elements[:xlabel] = xlabeltext
    elements[:ylabel] = ylabeltext
    # Register the spine as a decoration (excluded from data limits) AND as the projection-domain
    # outline that `getlimits` clamps the data window to (cartopy's `projection.x_limits`). See
    # getlimits in makie-axis.jl.
    elements[:spine] = spineplot

    subtitlepos = lift(axis.blockscene, scene.viewport, axis.titlegap, axis.titlealign, axis.xaxisposition;
        ignore_equal_values=true) do a,
    titlegap, align, xaxisposition
        xaxisprotrusion = 0f0
        align_factor = Makie.halign2num(align, "Horizontal title align $align not supported.")
        x = a.origin[1] + align_factor * a.widths[1]

        yoffset = Makie.top(a) + titlegap + (xaxisposition === (:top) ? xaxisprotrusion : 0.0f0)

        return Point2d(x, yoffset)
    end

    titlealignnode = lift(axis.blockscene, axis.titlealign; ignore_equal_values=true) do align
        (align, :bottom)
    end

    subtitlet = text!(
        axis.blockscene, subtitlepos,
        text=axis.subtitle,
        visible=axis.subtitlevisible,
        fontsize=axis.subtitlesize,
        align=titlealignnode,
        font=axis.subtitlefont,
        color=axis.subtitlecolor,
        lineheight=axis.subtitlelineheight,
        markerspace=:data,
        inspectable=false)

    titlepos = lift(Makie.calculate_title_position, axis.blockscene, scene.viewport, axis.titlegap, axis.subtitlegap,
        axis.titlealign, axis.xaxisposition, Observable(0f0), axis.subtitlelineheight, axis, subtitlet; ignore_equal_values=true)

    titlet = text!(
        axis.blockscene, titlepos,
        text=axis.title,
        visible=axis.titlevisible,
        fontsize=axis.titlesize,
        align=titlealignnode,
        font=axis.titlefont,
        color=axis.titlecolor,
        lineheight=axis.titlelineheight,
        markerspace=:data,
        inspectable=false)

    # Exact protrusions from the actual decoration extents (see layout.jl). This
    # must run after the title/subtitle plots exist because it measures them
    # directly. Values are only published when they change materially, so the
    # layout loop can converge instead of oscillating.
    last_protrusions = Ref(GridLayoutBase.RectSides{Float32}(-1.0f0, -1.0f0, -1.0f0, -1.0f0))
    onany(axis.blockscene, axis.title, axis.titlesize, axis.titlegap, axis.titlevisible,
        decoration_extents,
        axis.subtitle, axis.subtitlevisible, axis.subtitlesize, axis.subtitlegap,
        axis.titlelineheight, axis.subtitlelineheight, subtitlet, titlet) do title, titlesize,
            titlegap, titlevisible, dextents, subtitle, subtitlevisible, subtitlesize,
            subtitlegap, titlelineheight, subtitlelineheight, st, tt
        newp = compute_protrusions(title, titlesize, titlegap, titlevisible,
            dextents, subtitle, subtitlevisible, subtitlesize, subtitlegap,
            titlelineheight, subtitlelineheight, st, tt)
        old = last_protrusions[]
        changed = any(
            abs(getfield(newp, s) - getfield(old, s)) > 0.25
            for s in (:left, :right, :bottom, :top)
        )
        if changed
            last_protrusions[] = newp
            axis.layoutobservables.protrusions[] = newp
        end
        return
    end

    fl = axis.finallimits[]
    notify(axis.limits)
    if fl == axis.finallimits[]
        notify(axis.finallimits)
    end

    return axis
end

# This is where we override the stuff to make it our stuff.
function Makie.plot!(axis::GeoAxis, plot::Makie.AbstractPlot)
    # deal with setting the transform_func correctly
    source = pop!(plot.kw, :source, axis.source)
    transformfunc = lift(create_transform, axis.dest, source)

    if !Makie.not_in_data_space(plot)
        trans = Makie.Transformation(transformfunc; get(plot.kw, :transformation, Attributes())...)
        plot.kw[:transformation] = trans
    end

    # remove the reset_limits kwarg if there is one, this determines whether to automatically reset limits
    # on plot insertion
    reset_limits = to_value(pop!(plot.kw, :reset_limits, true))
    
    # actually plot
    Makie.plot!(axis.scene, plot)

    # reset limits ONLY IF the user has not said otherwise
    if reset_limits
        # some area-like plots (meshimage/surface) look better covering the whole plot area, so
        # tighten the margins, but keep a 1% sliver rather than (0,0) so the projection-boundary
        # spine, drawn at the very edge of the projected domain, isn't half-clipped by the axis.
        if Makie.needs_tight_limits(plot)
            axis.xautolimitmargin = (0.01, 0.01)
            axis.yautolimitmargin = (0.01, 0.01)
        end

        if Makie.is_open_or_any_parent(axis.scene)
            Makie.reset_limits!(axis)
        end
    end

    return plot
end


# This function only exists to get around the attribute name check,
# since source and dest are not listed as common attributes.
# All crs handling is done in `plot!(ax::GeoAxis, plot)`.
function _create_plot!(F, attributes::Dict, ax::GeoAxis, args...)
    source = pop!(attributes, :source, nothing)
    dest = pop!(attributes, :dest, nothing)
    plot = Plot{Makie.default_plot_func(F, args)}(args, attributes)
    isnothing(source) || (plot.kw[:source] = source)
    isnothing(dest) || (plot.kw[:dest] = dest)
    Makie.plot!(ax, plot)
    return plot
end


# ## Makie generic axis/block API

# this is generally false, but I want to deviate from that here.
Makie.needs_tight_limits(axis::GeoAxis, ::Surface) = true

Makie.get_scene(ga::GeoAxis) = ga.scene
