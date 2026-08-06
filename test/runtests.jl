using GeoMakie, GeometryBasics, Test
import Makie.SpecApi as S

# Backend-selectable test runner: `GEOMAKIE_TEST_BACKEND=gl` runs the same suite
# with GLMakie active (used by CI); the default is CairoMakie.
if lowercase(get(ENV, "GEOMAKIE_TEST_BACKEND", "cairo")) == "gl"
    using CairoMakie, GLMakie
    GLMakie.activate!()
else
    using CairoMakie
end

Makie.set_theme!(Theme(
    Heatmap = (rasterize = 5,),
    Image   = (rasterize = 5,),
    Surface = (rasterize = 5,),
))
@testset "GeoMakie" begin
    @testset "Basics" include("basics.jl")
    @testset "SphereClip" include("sphere_clip.jl")
    @testset "PR381Fixes" include("pr381_fixes.jl")
    @testset "GeoAxisV2" include("geoaxis_v2.jl")
    @testset "WrappedLimits" include("wrapped_limits.jl")
    @testset "Linking" include("linking.jl")
    @testset "Caching" include("caching.jl")
    @testset "Boundaries" include("boundaries.jl")
    @testset "MeshImage" include("meshimage.jl")
    @testset "GeoAxis" include("geoaxis.jl")
    @testset "PolarGeoAxis" include("polar_geoaxis.jl")
    @testset "GlobeAxis" include("globeaxis.jl")
end
