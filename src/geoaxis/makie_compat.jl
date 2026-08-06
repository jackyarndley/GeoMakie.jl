#= GeoAxis v2 — copied Makie-private compatibility code

These functions are copied (or closely adapted) from Makie's private axis
internals because Makie 0.24 does not expose them. Each entry documents the
original location and the smallest upstream API that would remove the copy.

The smallest useful upstream changes would be:

- expose `Makie.data_limits` building blocks (`point_iterator` for grid plots,
  `limits_from_transformed_points`, `transformed_limits`) as public helpers;
- expose the rectangle-zoom selection-vertex projection so backends/derived
  axes do not need to reimplement `_selection_vertices_notransform`.
=#

# Original: Makie `src/makielayout/blocks/axis.jl` (data-limit helpers).
function br_getindex(vector::AbstractVector, idx::CartesianIndex, dim::Int)
    return vector[Tuple(idx)[dim]]
end

function br_getindex(matrix::AbstractMatrix, idx::CartesianIndex, dim::Int)
    return matrix[idx]
end

function get_point_xyz(linear_indx::Int, indices, X, Y, Z)
    idx = indices[linear_indx]
    x = br_getindex(X, idx, 1)
    y = br_getindex(Y, idx, 2)
    z = Z[linear_indx]
    if z isa Number
        return Point3d(x, y, z)
    else
        return Point3d(x, y, 0)
    end
end

function get_point_xyz(linear_indx::Int, indices, X, Y)
    idx = indices[linear_indx]
    x = br_getindex(X, idx, 1)
    y = br_getindex(Y, idx, 2)
    return Point3d(x, y, 0.0)
end

function _point_iterator(plot::Union{Image, Heatmap, Surface})
    Z = plot[3][]
    X = to_vector(plot[1][], size(Z, 1), Float64)
    Y = to_vector(plot[2][], size(Z, 2), Float64)
    indices = CartesianIndices(Z)
    return Point3d[get_point_xyz(idx, indices, X, Y, Z) for idx in 1:length(Z)]
end

function _point_iterator(list::AbstractVector)
    if length(list) == 1
        # save a copy!
        return _point_iterator(list[1])
    else
        points = Point3d[]
        for elem in list
            for point in _point_iterator(elem)
                push!(points, to_ndim(Point33d, point, 0))
            end
        end
        return points
    end
end

function _point_iterator(plot::Plot)
    if isempty(plot.plots)
        return Makie.point_iterator(plot)
    end
    return _point_iterator(plot.plots)
end

function limits_from_transformed_points(points_iterator)
    isempty(points_iterator) && return Rect3d()
    first, rest = Iterators.peel(points_iterator)
    bb = foldl(Makie._update_rect, rest, init = Rect3{Float64}(first, zero(first)))
    return bb
end

# include bbox from scaled markers
function limits_from_transformed_points(positions, scales, rotations, element_bbox)
    isempty(positions) && return Rect3d()

    first_scale = attr_broadcast_getindex(scales, 1)
    first_rot = attr_broadcast_getindex(rotations, 1)
    full_bbox = Ref(first_rot * (element_bbox * first_scale) + first(positions))
    for (i, pos) in enumerate(positions)
        scale, rot = attr_broadcast_getindex(scales, i), attr_broadcast_getindex(rotations, i)
        transformed_bbox = rot * (element_bbox * scale) + pos
        update_boundingbox!(full_bbox, transformed_bbox)
    end

    return full_bbox[]
end

function transformed_limits(scenelike, exclude = (p) -> false)
    bb_ref = Base.RefValue(Rect3d())
    Makie.foreach_plot(scenelike) do plot
        if !exclude(plot)
            box = limits_from_transformed_points(Makie.iterate_transformed(plot))
            Makie.update_boundingbox!(bb_ref, box)
        end
    end
    return bb_ref[]
end

# Original: Makie `src/makielayout/blocks/axis.jl` (`RectangleZoom` selection
# vertices). Required so the selection overlay is drawn in the block scene
# (pixel space) while the axis scene stays exclusive to user plots.
function _selection_vertices_notransform(ax_scene, outer, inner)
    _clamp(p, plow, phigh) = Point2(clamp(p[1], plow[1], phigh[1]), clamp(p[2], plow[2], phigh[2]))
    proj(point) = Makie.project(ax_scene, point) + Makie.origin(Makie.to_value(Makie.viewport(ax_scene)))
    outer = Makie.positivize(outer)
    inner = Makie.positivize(inner)

    obl = Makie.bottomleft(outer)
    obr = Makie.bottomright(outer)
    otl = Makie.topleft(outer)
    otr = Makie.topright(outer)

    ibl = _clamp(Makie.bottomleft(inner), obl, otr)
    ibr = _clamp(Makie.bottomright(inner), obl, otr)
    itl = _clamp(Makie.topleft(inner), obl, otr)
    itr = _clamp(Makie.topright(inner), obl, otr)
    # We plot the selection vertices in blockscene, which is pixelspace, so we need to manually
    # project the points to the space of `ax.scene`
    return [proj(obl), proj(obr), proj(otr), proj(otl), proj(ibl), proj(ibr), proj(itr), proj(itl)]
end
