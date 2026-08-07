#=
# Seam-aware filled contours on a `GeoAxis`

`contourf` builds filled-band polygons in lon/lat; on a projection with a discontinuity
those bands smear across the tear. We intercept the recipe: split each band polygon on the
sphere via [`clip_fill`](@ref) (chosen by [`clip_strategy`](@ref)), then swap the child
`Poly` to draw the split polygons. Output stays in lon/lat, so the child still projects
per-vertex through the GeoAxis transform.
=#

# First child plot of `plot` that is a `T` (the atomic plot the recipe built).
function _find_child(plot, ::Type{T}) where {T}
    i = findfirst(p -> p isa T, plot.plots)
    return i === nothing ? nothing : plot.plots[i]
end

# Hide a recipe child whose `:visible` is a computed output (setting
# `child.visible = false` would try to add an input that already exists).
function _hide_child!(p)
    c = p[:visible]
    c[]           # resolve first so the value ref is assigned
    c[] = false
    return p
end

# Freeze and hide a recipe's own (unsplit) child. The compute graph is detached
# from the parent so its geometry/`:visible` can never be re-derived (which
# would resurrect the unsplit drawing after a hide/show cycle); the split child
# handles all subsequent updates. The returned plot's own visibility still
# gates the child through the backend's parent-tree checks.
function _freeze_hide_child!(child)
    Makie.ComputePipeline.unsafe_disconnect_from_parents!(child.attributes)
    _hide_child!(child)
    return child
end

# Link a child plot's visibility to its parent so hiding/deleting the returned
# plot affects its rendered children in every backend (Cairo already gates child
# drawing on the parent tree; GLMakie renders children independently).
function _link_child_visibility(parent::Makie.Plot, child::Makie.Plot)
    c = child[:visible]
    c[]           # resolve first so the value ref is assigned
    on(parent, parent.visible; update = true) do v
        c[] = v
    end
    return child
end

# Split each band polygon at the clip's discontinuity (full d3 pipeline: rotate → clip →
# resample), replicating its colour onto every resulting piece. `polys`/`colors` are parallel
# vectors from the `contourf` recipe; `project`/`scale` drive the adaptive resampler.
function _split_polys_colors(polys, colors, clip::SphereClip, project, scale; rotated::Bool = false)
    newpolys = GeometryBasics.Polygon{2,Float32}[]
    newcolors = eltype(colors)[]
    for (poly, col) in zip(polys, colors)
        for np in _split_polygon(clip, _poly_rings(poly), project, scale; rotated = rotated, winding = :planar)
            push!(newpolys, np); push!(newcolors, col)
        end
    end
    return (newpolys, newcolors)
end

function Makie.plot!(axis::GeoAxis, plot::Makie.Contourf)
    # mirror the generic GeoAxis transform injection (geoaxis.jl `plot!(::GeoAxis, ::AbstractPlot)`)
    source = pop!(plot.kw, :source, axis.source)
    transformfunc = lift(create_transform, axis.dest, source)
    if !Makie.not_in_data_space(plot)
        plot.kw[:transformation] = Makie.Transformation(transformfunc; get(plot.kw, :transformation, Attributes())...)
    end
    reset_limits = to_value(pop!(plot.kw, :reset_limits, true))

    Makie.plot!(axis.scene, plot)   # run the contourf recipe → builds the child Poly

    Makie.register_computation!(
        plot.attributes,
        [:polys, :computed_colors, :transform_func],
        [:split_polys, :split_colors],
    ) do (polys, colors, tfunc), changed, cached
        rctx = ProjectionRenderContext(to_value(axis.dest), to_value(source))
        rctx.clip isa NoClip && return (polys, colors)
        # Option B: clip/resample in the canonical rotated frame and draw with the centred
        # projector (lon_0=0 / native centred), avoiding PROJ's half-open longitude-wrap
        # collapsing the seam onto one map edge (the moll +lon_0=180 bug, bertin's ±π seam).
        return _split_polys_colors(polys, colors, rctx.clip, rctx.projector,
            rctx.resample_scale; rotated = rctx.rotated)
    end

    # The split child must draw in the SAME frame the split polys were emitted in: centred
    # transform for the antimeridian (rotated frame), full transform otherwise, decided inside one
    # lift (`_child_transformfunc`) so the geometry frame and transform switch atomically with `dest`.
    # The recipe's own unsplit child is hidden (not removed from `plot.plots`), and the split child
    # is a child of the returned recipe so hiding/deleting the handle affects its rendering.
    child = _find_child(plot, Makie.Poly)
    if child !== nothing
        _freeze_hide_child!(child)
        splitchild = Makie.poly!(
            plot, plot.split_polys;
            transformation = Makie.Transformation(_child_transformfunc(axis, source)),
            colormap = plot.computed_colormap,
            colorrange = plot.computed_colorrange,
            highclip = plot.computed_highcolor,
            lowclip = plot.computed_lowcolor,
            nan_color = plot.nan_color,
            color = plot.split_colors,
            strokewidth = 0,
            strokecolor = :transparent,
            shading = Makie.NoShading,
            inspectable = plot.inspectable,
            transparency = plot.transparency,
        )
        _link_child_visibility(plot, splitchild)
    end

    if reset_limits
        Makie.needs_tight_limits(plot) && Makie.tightlimits!(axis)
        Makie.is_open_or_any_parent(axis.scene) && Makie.reset_limits!(axis)
    end
    return plot
end

# The transform the split child must draw with: centred (lon_0=0) for the antimeridian seam
# (Option B, geometry is emitted in the rotated frame), the full transform otherwise.
function _child_transformfunc(axis, source)
    lift(axis.dest, source) do dest, src
        ProjectionRenderContext(dest, src).display_transform
    end
end

# Yield `(user_index, polygon)` pairs for a user geometry: one entry per flattened polygon,
# tagged with the index of the user Polygon/MultiPolygon it came from. This lets per-element
# colour vectors (one colour per user polygon/MultiPolygon) be replicated onto every piece
# even when `_collect_polys` expands MultiPolygon components.
function _user_polys(geom)
    if geom isa GeometryBasics.Polygon || geom isa GeometryBasics.MultiPolygon
        return Tuple{Int, GeometryBasics.Polygon{2, Float32}}[(1, p) for p in _collect_polys(geom)]
    elseif geom isa AbstractVector
        pairs = Tuple{Int, GeometryBasics.Polygon{2, Float32}}[]
        for (k, g) in enumerate(geom)
            for p in _collect_polys(g)
                push!(pairs, (k, p))
            end
        end
        return pairs
    else
        return Tuple{Int, GeometryBasics.Polygon{2, Float32}}[(1, p) for p in _collect_polys(geom)]
    end
end

# Split a vector of polygons at the destination discontinuity in the correct frame, returning
# the split polygons and a `group` vector mapping each output piece back to its input user
# geometry element (so per-element colours can be replicated). Mirrors the contourf path.
function _split_geom(geom, dest, source)
    rctx = ProjectionRenderContext(dest, source)
    clip = rctx.clip
    polys = GeometryBasics.Polygon{2,Float32}[]; group = Int[]
    user_pairs = _user_polys(geom)
    clip isa NoClip && (for (k, p) in user_pairs; push!(polys, p); push!(group, k); end; return (polys, group))
    for (k, p) in user_pairs
        pieces = _split_polygon(clip, _poly_rings(p), rctx.projector,
            rctx.resample_scale; rotated = rctx.rotated)
        append!(polys, pieces); append!(group, fill(k, length(pieces)))
    end
    return (polys, group)
end

# ============================================================================
# Seam-aware `poly!`/`lines!` composite recipes.
#
# `poly!(ga, geom)` and `lines!(ga, pts)` return a small composite recipe whose
# only child is the seam-split, frame-correct rendering. Hiding/deleting the
# returned plot behaves like any other Makie composite recipe (no hidden
# originals, no scene siblings, no `plot.plots` mutation), and attributes are
# forwarded through the compute graph to the child.
# ============================================================================

# Marker types: the recipe argument carries the user geometry. The CRS values
# live in the recipe's `source`/`dest` attributes (set by the axis method) so
# the argument itself contains no Observables — ComputePipeline deep-copies
# computed arguments, and an Observable inside the marker would drag the whole
# axis graph into the copy.
struct _GeoSeamPolyArg{A}
    args::A
end

struct _GeoSeamLinesArg{A}
    args::A
end

@recipe GeoSeamPoly (geom,) begin
    "Color of the polygon fill(s)."
    color = automatic
    "Color of the polygon outlines."
    strokecolor = :black
    "Width of the polygon outlines."
    strokewidth = 1.0
    "Lighting algorithm used by 3D backends."
    shading = Makie.NoShading
    "Geographic source CRS (PROJ string or GeoFormatTypes object)."
    source = "+proj=longlat +datum=WGS84"
    "Destination CRS / projection (PROJ string or GeoFormatTypes object)."
    dest = "+proj=longlat +datum=WGS84"
    "Whether to reset the axis limits when the plot is added."
    reset_limits = true
    mixin_generic_plot_attributes()...
    mixin_colormap_attributes()...
end

@recipe GeoSeamLines (pts,) begin
    "Color of the line(s)."
    color = automatic
    "Width of the line(s)."
    linewidth = 1.0
    "Style of the line(s)."
    linestyle = nothing
    "Geographic source CRS (PROJ string or GeoFormatTypes object)."
    source = "+proj=longlat +datum=WGS84"
    "Destination CRS / projection (PROJ string or GeoFormatTypes object)."
    dest = "+proj=longlat +datum=WGS84"
    "Whether to reset the axis limits when the plot is added."
    reset_limits = true
    mixin_generic_plot_attributes()...
    mixin_colormap_attributes()...
end

Makie.convert_arguments(::Type{<:GeoSeamPoly}, m::_GeoSeamPolyArg) = (m,)
Makie.convert_arguments(::Type{<:GeoSeamLines}, m::_GeoSeamLinesArg) = (m,)

_is_poly_geometry(::GeometryBasics.Polygon) = true
_is_poly_geometry(::GeometryBasics.MultiPolygon) = true
_is_poly_geometry(::AbstractVector{<:GeometryBasics.Polygon}) = true
_is_poly_geometry(::AbstractVector{<:GeometryBasics.MultiPolygon}) = true
_is_poly_geometry(::AbstractVector{<:AbstractVector{<:Point}}) = true
_is_poly_geometry(_...) = false

_is_line_geometry(::AbstractVector{<:Point2}) = true
_is_line_geometry(::AbstractVector{<:Number}, ::AbstractVector{<:Number}) = true
_is_line_geometry(_...) = false

# The transform the split child must draw with (the same Option-B rule as
# `_child_transformfunc`, from arbitrary dest/source values).
function _display_transform_obs(dest, source)
    return lift(dest, source) do d, s
        ProjectionRenderContext(d, s).display_transform
    end
end

_geo_poly_geometry(m::_GeoSeamPolyArg) = length(m.args) == 1 ? m.args[1] : m.args

function _geo_line_points(m::_GeoSeamLinesArg)
    length(m.args) == 1 && return m.args[1]
    xs, ys = m.args
    return Point2d[Point2d(x, y) for (x, y) in zip(xs, ys)]
end

function Makie.plot!(plot::GeoSeamPoly)
    m = plot[1][]
    split = lift(plot[1], plot.dest, plot.source) do m2, d, s
        _split_geom(_geo_poly_geometry(m2), d, s)
    end
    splitpolys = lift(first, split)
    splitcolor = lift(plot.color, plot[1], split) do col, m2, s
        # `s[2]` maps every flattened/clipped output piece back to its input
        # geometry element. Per-element colour vectors (one colour per user
        # polygon/MultiPolygon) are replicated onto the pieces; the input count
        # is the user-geometry length, not the flattened piece count.
        geom = _geo_poly_geometry(m2)
        ninput = geom isa AbstractVector ? length(geom) : 1
        (col isa AbstractVector && length(col) == ninput) ? col[s[2]] : col
    end
    color_kw = to_value(plot.color) === Makie.automatic ?
        NamedTuple() : (color = splitcolor,)
    splitchild = Makie.poly!(plot, splitpolys;
        color_kw...,
        colormap = plot.colormap,
        colorrange = plot.colorrange,
        strokecolor = plot.strokecolor,
        strokewidth = plot.strokewidth,
        transparency = plot.transparency,
        transformation = Makie.Transformation(_display_transform_obs(plot.dest, plot.source)),
    )
    _link_child_visibility(plot, splitchild)
    return plot
end

function Makie.plot!(plot::GeoSeamLines)
    m = plot[1][]
    splitpts = lift(plot[1], plot.dest, plot.source) do m2, d, s
        rctx = ProjectionRenderContext(d, s)
        split_resample_line(_geo_line_points(m2), rctx.geographic_transform;
            project = rctx.projector, rotated = rctx.rotated)
    end
    # Per-vertex colours cannot survive adaptive resampling (the vertex count
    # changes); fall back to a single colour. Single colours pass through.
    splitcolor = lift(plot.color) do c
        c isa AbstractVector ? :black : c
    end
    color_kw = to_value(plot.color) === Makie.automatic ?
        NamedTuple() : (color = splitcolor,)
    splitchild = Makie.lines!(plot, splitpts;
        color_kw...,
        colormap = plot.colormap,
        colorrange = plot.colorrange,
        linewidth = plot.linewidth,
        linestyle = plot.linestyle,
        transparency = plot.transparency,
        transformation = Makie.Transformation(_display_transform_obs(plot.dest, plot.source)),
    )
    _link_child_visibility(plot, splitchild)
    return plot
end

function Makie.plot!(axis::GeoAxis, plot::GeoSeamPoly)
    get(plot.kw, :source, nothing) === nothing && (plot.kw[:source] = axis.source)
    get(plot.kw, :dest, nothing) === nothing && (plot.kw[:dest] = axis.dest)
    reset_limits = to_value(pop!(plot.kw, :reset_limits, true))
    Makie.plot!(axis.scene, plot)
    reset_limits && Makie.is_open_or_any_parent(axis.scene) && Makie.reset_limits!(axis)
    return plot
end

function Makie.plot!(axis::GeoAxis, plot::GeoSeamLines)
    get(plot.kw, :source, nothing) === nothing && (plot.kw[:source] = axis.source)
    get(plot.kw, :dest, nothing) === nothing && (plot.kw[:dest] = axis.dest)
    reset_limits = to_value(pop!(plot.kw, :reset_limits, true))
    Makie.plot!(axis.scene, plot)
    reset_limits && Makie.is_open_or_any_parent(axis.scene) && Makie.reset_limits!(axis)
    return plot
end

# Seam-aware line contours: run the `contour` recipe, then swap its `Lines` child for the
# clipped/resampled version (drawn in the matching centred/full frame).
function Makie.plot!(axis::GeoAxis, plot::Makie.Contour)
    source = pop!(plot.kw, :source, axis.source)
    reset_limits = to_value(pop!(plot.kw, :reset_limits, true))
    plot.kw[:transformation] = Makie.Transformation(lift(create_transform, axis.dest, source))
    Makie.plot!(axis.scene, plot)        # contour recipe → Text (labels) + Lines

    child = _find_child(plot, Makie.Lines)
    if child !== nothing
        splitpts = lift(child[1], axis.dest, source) do pts, dest, src
            rctx = ProjectionRenderContext(dest, src)
            split_resample_line(pts, rctx.geographic_transform;
                project = rctx.projector, rotated = rctx.rotated)
        end
        col = lift(c -> c isa AbstractVector ? :black : c, child.color)   # per-vertex colour can't survive resampling
        _freeze_hide_child!(child)
        splitchild = Makie.lines!(
            plot, splitpts;
            color = col,
            linewidth = child.linewidth,
            linestyle = child.linestyle,
            transparency = plot.transparency,
            transformation = Makie.Transformation(_child_transformfunc(axis, source)),
        )
        _link_child_visibility(plot, splitchild)
    end
    reset_limits && Makie.is_open_or_any_parent(axis.scene) && Makie.reset_limits!(axis)
    return plot
end

# Build a projected, discontinuity-clipped triangle mesh from a rectilinear lon/lat grid
# (`xs`, `ys` vectors) with per-vertex values `vals`. The grid is projected (Option B: rotated
# frame + centred projector, for the antimeridian, so lon_0=180 doesn't collapse), triangulated,
# and faces straddling the tear are subdivided/dropped (`_clip_faces`). Returns (mesh, flat colour vector).
function _geo_grid_mesh(dest, source, xs, ys, vals)
    rctx = ProjectionRenderContext(dest, source)
    clip = rctx.clip
    # The mesh's canonical frame is the longitude-rotated frame (Option B for the
    # antimeridian, so lon_0=180 doesn't collapse). Oblique rotations are full 3-D
    # rotations with no single longitude shift, so the rectilinear grid keeps
    # geographic coordinates and the full transform.
    rotated = clip isa AntimeridianClip
    tf = rotated ? rctx.display_transform : rctx.geographic_transform
    lon0 = rotated ? clip.lon0 : 0.0
    # heatmap passes cell EDGES (n+1) with per-cell data (n); use centres so the vertex grid
    # matches `vals`. surface passes coordinate vectors matching `vals` already.
    nx, ny = size(vals)
    xs = length(xs) == nx + 1 ? [(xs[i] + xs[i+1]) / 2 for i in 1:nx] : xs
    ys = length(ys) == ny + 1 ? [(ys[j] + ys[j+1]) / 2 for j in 1:ny] : ys
    points = Vector{Point3d}(undef, nx * ny)
    latlon = Vector{Point2d}(undef, nx * ny)
    # Per-vertex values are either scalars (colormapped downstream) or explicit colours
    # (`surface!(...; color = <image>)`); `similar` inherits either eltype, so no Float64(::RGBA).
    cols = similar(vals, nx * ny)
    for (k, ci) in enumerate(CartesianIndices((nx, ny)))
        lo = Float64(xs[ci[1]]); la = Float64(ys[ci[2]])
        rotated && (lo = mod(lo - lon0 + 180.0, 360.0) - 180.0)   # canonical rotated frame
        latlon[k] = Point2d(lo, la)
        points[k] = Makie.to_ndim(Point3d, Makie.apply_transform(tf, Point3d(lo, la, 0.0)), 0.0)
        cols[k] = vals[ci[1], ci[2]]
    end
    rect = GeometryBasics.Tessellation(Rect2f(0, 0, 1, 1), (nx, ny))
    faces = GeometryBasics.decompose(Makie.GLTriangleFace, rect)
    # clip faces at the discontinuity (subdivides toward the seam); interpolate colour onto the
    # inserted midpoint vertices so the mesh fills to the boundary instead of leaving a sliver.
    pts, _, faces2, parents = _clip_faces(points, latlon, faces, _mesh_projector(tf, 0.0))
    for k in (nx*ny+1):length(pts)
        a, b = parents[k]; push!(cols, (cols[a] + cols[b]) / 2)
    end
    return (GeometryBasics.Mesh(pts, faces2), cols)
end

# `surface!`/`heatmap!` on a GeoAxis: project the rectilinear lon/lat grid to a seam-clipped mesh
# (Option B for the antimeridian) and draw it with the data as per-vertex colour. Heatmap can't
# render curvilinear cells natively; surface projects but smears/collapses without this.
function _geo_grid_plot!(axis, plot, vals_node)
    source = pop!(plot.kw, :source, axis.source)
    reset_limits = to_value(pop!(plot.kw, :reset_limits, true))
    # Realize the original surface/heatmap but hide it: the seam-clipped mesh below does the
    # drawing, while the original keeps a computed colormapping so `Colorbar(fig, sf)` still works
    # (it extracts the colormap from the returned plot). The mesh is added as a CHILD of the
    # returned plot (composite-style), so hiding/deleting the handle affects its rendering.
    Makie.plot!(axis.scene, plot)
    # Surface's own recipe draws a Mesh child; hide it so only the seam-clipped mesh renders.
    # Heatmap has no children, and adding a child makes it composite in every backend (its own
    # atomic drawing is then skipped), so nothing extra needs hiding there.
    for own in plot.plots
        _freeze_hide_child!(own)
    end
    mc = lift(plot[1], plot[2], vals_node, axis.dest, source) do xs, ys, vals, dest, src
        _geo_grid_mesh(dest, src, xs, ys, vals)
    end
    meshchild = Makie.mesh!(
        plot, lift(first, mc);
        color = lift(last, mc),
        colormap = plot.colormap,
        colorrange = plot.colorrange,
        nan_color = plot.nan_color,
        shading = Makie.NoShading,
        transparency = plot.transparency,
        # Mesh vertices are already projected; do not re-apply the axis transform.
        transformation = Makie.Transformation(),
    )
    _link_child_visibility(plot, meshchild)
    if reset_limits
        Makie.needs_tight_limits(plot) && (axis.xautolimitmargin = (0.01, 0.01); axis.yautolimitmargin = (0.01, 0.01))
        Makie.is_open_or_any_parent(axis.scene) && Makie.reset_limits!(axis)
    end
    return plot
end

# A colour image passed as `surface!(...; color = img)` may be finer than the z grid (which
# sets the mesh/geometry resolution). CairoMakie meshes can't texture-map, so sample `img`
# onto the grid as per-vertex colours instead of dropping it (which rendered a flat colour).
function _resample_to_grid(img, nx, ny)
    sx, sy = size(img)
    (sx == nx && sy == ny) && return img
    out = Matrix{eltype(img)}(undef, nx, ny)
    @inbounds for j in 1:ny, i in 1:nx
        ai = clamp(round(Int, (i - 0.5) * sx / nx + 0.5), 1, sx)
        aj = clamp(round(Int, (j - 0.5) * sy / ny + 0.5), 1, sy)
        out[i, j] = img[ai, aj]
    end
    return out
end

function Makie.plot!(axis::GeoAxis, plot::Makie.Surface)
    vals = lift(plot[3], plot.color) do zs, col
        col isa AbstractMatrix ? _resample_to_grid(col, size(zs, 1), size(zs, 2)) : zs
    end
    return _geo_grid_plot!(axis, plot, vals)
end

Makie.plot!(axis::GeoAxis, plot::Makie.Heatmap) = _geo_grid_plot!(axis, plot, plot[3])
