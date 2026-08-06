@testset "PR 381 regression fixes" begin
    @testset "add_cyclic_point is exported" begin
        lons = 0.0:30.0:330.0
        data = reshape(1:length(lons), length(lons), 1)
        lons_c, data_c = GeoMakie.add_cyclic_point(lons, data)
        @test lons_c[end] == 360.0
        @test data_c[end, 1] == data[1, 1]
    end

    @testset "per-vertex line colour falls back after resampling" begin
        fig = Figure()
        ga = GeoAxis(fig[1, 1]; dest = "+proj=moll")
        pts = Point2d[Point2d(-170, 10), Point2d(170, 20)]
        @test_nowarn lines!(ga, pts; color = 1:length(pts))
        @test_nowarn Makie.update_state_before_display!(fig)
    end

    @testset "seam-aware poly! covers single and multi polygons" begin
        single = GeometryBasics.Polygon(Point2d[Point2d(0, 0), Point2d(10, 0), Point2d(10, 10), Point2d(0, 10)])
        multi = GeometryBasics.MultiPolygon([single])
        fig = Figure()
        ga = GeoAxis(fig[1, 1]; dest = "+proj=moll")
        @test_nowarn poly!(ga, single)
        @test_nowarn poly!(ga, multi)
        @test_nowarn poly!(ga, [multi])
        @test_nowarn Makie.update_state_before_display!(fig)
    end
end
