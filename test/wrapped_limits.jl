using GeoMakie, CairoMakie, GeometryBasics, LinearAlgebra, Test
using Makie.GridLayoutBase
const G = GeoMakie

@testset "Wrapped geographic limits" begin
    @testset "LongitudeInterval semantics" begin
        x = G.LongitudeInterval(160, -160)
        @test x.wrap
        @test G.width(x) ≈ 40
        @test 170 in x
        @test -170 in x
        @test 0 ∉ x

        @test !G.LongitudeInterval(170, 190).wrap
        @test G.width(G.LongitudeInterval(170, 190)) ≈ 20
        @test G.width(G.LongitudeInterval(-190, -170)) ≈ 20
        @test G.LongitudeInterval(-190, -170).west ≈ 170

        full = G.LongitudeInterval(0, 360)
        @test G.width(full) ≈ 360
        @test 0 in full
        @test 180 in full

        w = G.LongitudeInterval(350, 20)
        @test w.wrap
        @test G.width(w) ≈ 30
        @test 355 in w
        @test 10 in w
        @test 100 ∉ w

        pieces = G.split_at_seam(G.LongitudeInterval(160, -160), [-180.0, 180.0])
        @test pieces == [(160.0, 180.0), (180.0, 200.0)]
        pieces2 = G.split_at_seam(G.LongitudeInterval(170, 190), [-180.0, 180.0])
        @test pieces2 == [(170.0, 180.0), (180.0, 190.0)]
        @test length(G.split_at_seam(full, [-180.0, 180.0])) == 1
    end

    @testset "geolimits! on a cylindrical projection" begin
        fig = Figure()
        ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        geolimits!(ga, 160, -160, -60, 60)
        Makie.update_state_before_display!(fig)
        fl = ga.finallimits[]
        @test all(isfinite, (minimum(fl)[1], maximum(fl)[1], minimum(fl)[2], maximum(fl)[2]))
        @test maximum(fl)[1] - minimum(fl)[1] > 0

        geolimits!(ga, 350, 20, -60, 60)
        Makie.update_state_before_display!(fig)
        @test all(isfinite, (minimum(ga.finallimits[])[1], maximum(ga.finallimits[])[1]))

        geolimits!(ga, 0, 360, -90, 90)
        Makie.update_state_before_display!(fig)
        fl = ga.finallimits[]
        # full period: projected span is the whole map
        @test maximum(fl)[1] - minimum(fl)[1] > 1.0e7
    end

    @testset "xlims! preserves wrapped intervals" begin
        fig = Figure()
        ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        xlims!(ga, 160, -160)
        @test ga.limits[][1] isa G.LongitudeInterval
        Makie.update_state_before_display!(fig)
        @test all(isfinite, (minimum(ga.finallimits[])[1], maximum(ga.finallimits[])[1]))
        @test !ga.xreversed[]

        xlims!(ga, 170, 190)
        Makie.update_state_before_display!(fig)
        @test all(isfinite, (minimum(ga.finallimits[])[1], maximum(ga.finallimits[])[1]))
    end

    @testset "geolimits! on a polar GeoAxis" begin
        fig = Figure()
        ga = GeoAxis(fig[1, 1];
            dest = "+proj=stere +lat_0=90 +lon_0=0 +datum=WGS84")
        geolimits!(ga, 160, -160, 60, 90)
        Makie.update_state_before_display!(fig)
        fl = ga.finallimits[]
        @test all(isfinite, (minimum(fl)[1], maximum(fl)[1], minimum(fl)[2], maximum(fl)[2]))
        @test minimum(fl)[2] < maximum(fl)[2]
        @test (save(tempname() * ".png", fig); true)
    end

    @testset "projected_limits! sets the camera rectangle directly" begin
        fig = Figure()
        ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        projected_limits!(ga, -1.0e7, 1.0e7, -5.0e6, 5.0e6)
        @test ga.targetlimits[] == Makie.BBox(-1.0e7, 1.0e7, -5.0e6, 5.0e6)
        @test ga.finallimits[] == Makie.BBox(-1.0e7, 1.0e7, -5.0e6, 5.0e6)
        Makie.update_state_before_display!(fig)
        @test all(isfinite, (minimum(ga.finallimits[])[1], maximum(ga.finallimits[])[1]))
    end

    @testset "reset, autolimits and tight limits after wrapped limits" begin
        fig = Figure()
        ga = GeoAxis(fig[1, 1]; dest = "+proj=moll")
        lines!(ga, Point2d[Point2d(170, 10), Point2d(-170, 20)])
        geolimits!(ga, 160, -160, -30, 30)
        Makie.update_state_before_display!(fig)
        reset_limits!(ga)
        Makie.autolimits!(ga)
        Makie.tightlimits!(ga)
        @test (save(tempname() * ".png", fig); true)
    end
end
