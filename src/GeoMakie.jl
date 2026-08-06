module GeoMakie

using Statistics, LinearAlgebra

using Reexport

using GeometryBasics, Colors, ImageIO

using Makie


import Makie: _create_plot!, mixin_generic_plot_attributes, mixin_colormap_attributes

import Makie: convert_arguments, convert_attribute, to_value, automatic
using Makie, Makie.FileIO, Makie.GridLayoutBase, Makie.DocStringExtensions
using Makie: Format
using Makie.GridLayoutBase: Side

using GeoJSON, NaturalEarth # for data

import GeometryOps as GO, GeoInterface as GI
using GeoInterface: GeoInterface, coordinates, getfeature
using GeometryBasics: Polygon, MultiPolygon

using Geodesy
using Proj
import GeoFormatTypes

export GeoInterface

# bring in missing Makie methods required for block definition
using Makie: make_block_docstring

# fix conflicts
import Makie: rotate! # use LinearAlgebra.rotate! otherwise

const AbstractGeometry = GeometryBasics.AbstractGeometry
const Point = Makie.Point
const attributes = Makie.attributes
const volume = Makie.volume
const Mesh = GeometryBasics.Mesh
const Text = Makie.Text

# Quick fix for GeometryBasics
Base.convert(::Type{Rect{N, Float64}}, x::Rect{N}) where N = Rect{N, Float64}(x)

include("makie_piracy.jl")
include("geojson.jl") # GeoJSON/GeoInterface support
include("conversions.jl")
include("data.jl")
include("utils.jl")
include("geodesy.jl")
include("geoticks.jl")
include("projection.jl")
include("sphere_clip.jl") # sphere-space clipping + adaptive resampling for discontinuities

include("geoaxis/projection.jl") # GeoProjection + ProjectionTraits (GeoAxis v2)
include("geoaxis/boundaries.jl") # projection-domain boundary strategies (GeoAxis v2)
include("geoaxis/viewport.jl")   # geographic viewport state (GeoAxis v2)
include("geoaxis/graticule.jl")  # adaptive graticule engine (GeoAxis v2)
include("geoaxis/labels.jl")     # boundary-aware tick labels (GeoAxis v2)
include("geoaxis/layout.jl")     # exact decoration protrusions (GeoAxis v2)
include("geoaxis/longitude.jl")  # wrapped longitude intervals (GeoAxis v2)
include("geoaxis/caching.jl")    # bounded per-axis caches (GeoAxis v2)

include("geoaxis.jl")
include("geoaxis/makie_compat.jl")  # copied Makie-private compatibility code (GeoAxis v2)
include("contoursplitting_geo.jl") # seam-aware filled contours on a GeoAxis
include("makie-axis.jl")
include("geoaxis/linking.jl")      # geographic GeoAxis linking (GeoAxis v2)

# some basic recipes
include("mesh_image.jl")
include("linesplitting.jl")

include("sphere/unit_sphere_transforms.jl")
include("sphere/icosphere.jl")
include("sphere/globetransform.jl")
include("sphere/globeaxis.jl")

include("triangulation3d.jl")

@reexport using Colors, Makie
export Proj

export FileIO

export GeoAxis, add_cyclic_point, automatic
export geolimits!, projected_limits!, unlinkaxes!
export datalims, datalims!
@deprecate datalims Makie.autolimits
@deprecate datalims! Makie.reset_limits!

end # module
