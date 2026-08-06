using GeoMakie, CairoMakie, GeometryBasics, Test
const G = GeoMakie

@testset "GeoAxis geographic linking" begin
    @testset "linkxaxes! shares longitude only" begin
        fig = Figure()
        a1 = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        a2 = GeoAxis(fig[1, 2]; dest = "+proj=eqearth")
        linkxaxes!(a1, a2)
        geolimits!(a1, -60, 60, -30, 30)
        Makie.update_state_before_display!(fig)
        x2, y2 = G._geo_limits_from_limits(a2.limits[])
        @test x2 !== nothing
        @test G.width(x2) ≈ 120
        @test y2 === nothing
        @test a2.finallimits[] isa GeometryBasics.HyperRectangle{2, Float64}
    end

    @testset "linkyaxes! shares latitude only" begin
        fig = Figure()
        a1 = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        a2 = GeoAxis(fig[1, 2]; dest = "+proj=eqearth")
        linkyaxes!(a1, a2)
        ylims!(a1, -20, 40)
        Makie.update_state_before_display!(fig)
        x2, y2 = G._geo_limits_from_limits(a2.limits[])
        @test x2 === nothing
        @test y2 == (-20.0, 40.0)
    end

    @testset "linkaxes! shares geographic extent across projections" begin
        fig = Figure()
        a1 = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        a2 = GeoAxis(fig[1, 2]; dest = "+proj=ortho +lon_0=0 +lat_0=0")
        linkaxes!(a1, a2)
        geolimits!(a1, -60, 60, -30, 30)
        Makie.update_state_before_display!(fig)
        x2, y2 = G._geo_limits_from_limits(a2.limits[])
        @test G.width(x2) ≈ 120
        @test y2 == (-30.0, 30.0)
        # each axis projects independently
        @test a1.finallimits[] != a2.finallimits[]
    end

    @testset "different central meridians" begin
        fig = Figure()
        a1 = GeoAxis(fig[1, 1]; dest = "+proj=stere +lat_0=90 +lon_0=0")
        a2 = GeoAxis(fig[1, 2]; dest = "+proj=stere +lat_0=90 +lon_0=180")
        linkaxes!(a1, a2)
        geolimits!(a1, 0, 90, 60, 90)
        Makie.update_state_before_display!(fig)
        x2, y2 = G._geo_limits_from_limits(a2.limits[])
        @test G.width(x2) ≈ 90
        @test y2 == (60.0, 90.0)
        @test all(isfinite, (minimum(a2.finallimits[])[1], maximum(a2.finallimits[])[1]))
    end

    @testset "wrapped longitudes propagate" begin
        fig = Figure()
        a1 = GeoAxis(fig[1, 1]; dest = "+proj=moll")
        a2 = GeoAxis(fig[1, 2]; dest = "+proj=moll +lon_0=180")
        linkaxes!(a1, a2)
        geolimits!(a1, 160, -160, -30, 30)
        Makie.update_state_before_display!(fig)
        x2, _ = G._geo_limits_from_limits(a2.limits[])
        @test x2.wrap
        @test G.width(x2) ≈ 40
    end

    @testset "xlims! propagates wrapped intervals" begin
        fig = Figure()
        a1 = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        a2 = GeoAxis(fig[1, 2]; dest = "+proj=eqearth")
        linkxaxes!(a1, a2)
        xlims!(a1, 170, 190)
        Makie.update_state_before_display!(fig)
        x2, _ = G._geo_limits_from_limits(a2.limits[])
        @test x2 isa G.LongitudeInterval
        @test G.width(x2) ≈ 20
    end

    @testset "interactive camera changes propagate when limits are automatic" begin
        fig = Figure()
        a1 = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        a2 = GeoAxis(fig[1, 2]; dest = "+proj=ortho +lon_0=0 +lat_0=0")
        linkaxes!(a1, a2)
        autolimits!(a1)
        autolimits!(a2)
        a1.targetlimits[] = Makie.BBox(-1.0e7, 1.0e7, -5.0e6, 5.0e6)
        Makie.update_state_before_display!(fig)
        linked = a2.linked_geographic_limits[]
        @test linked isa G.GeographicLimits
        @test a2.limits[] == (nothing, nothing)
        @test all(isfinite, (minimum(a2.finallimits[])[1], maximum(a2.finallimits[])[1]))
    end

    @testset "unlinking stops propagation" begin
        fig = Figure()
        a1 = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        a2 = GeoAxis(fig[1, 2]; dest = "+proj=eqearth")
        linkaxes!(a1, a2)
        unlinkaxes!(a1, a2)
        @test isempty(a1.xaxislinks)
        @test isempty(a1.yaxislinks)
        @test isempty(a2.xaxislinks)
        geolimits!(a1, 0, 30, -10, 10)
        @test a2.limits[] == (nothing, nothing)
    end

    @testset "incompatible source CRSs error clearly" begin
        fig = Figure()
        a1 = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        a2 = GeoAxis(fig[1, 2]; dest = "+proj=eqearth", source = "+proj=merc")
        @test_throws ArgumentError linkaxes!(a1, a2)
    end
end
