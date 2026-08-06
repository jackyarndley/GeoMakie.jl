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

    @testset "per-row colours survive MultiPolygon flattening and seam splitting" begin
        # 49 user MultiPolygons (two with two components) flatten to 51 pieces;
        # the 49 per-row colours must be replicated onto the pieces so
        # CairoMakie can render the split child.
        mps = GeometryBasics.MultiPolygon{2, Float32}[]
        for i in 1:49
            p1 = GeometryBasics.Polygon(Point2f[(i - 1, 0), (i, 0), (i, 1), (i - 1, 1)])
            if i in (25, 26)
                p2 = GeometryBasics.Polygon(Point2f[(i - 1, 2), (i, 2), (i, 3), (i - 1, 3)])
                push!(mps, GeometryBasics.MultiPolygon([p1, p2]))
            else
                push!(mps, GeometryBasics.MultiPolygon([p1]))
            end
        end
        colors = fill(RGBAf(1, 0.9, 0, 1), length(mps))
        fig = Figure()
        ga = GeoAxis(fig[1, 1]; dest = "+proj=moll")
        @test_nowarn poly!(ga, mps; color = colors, strokecolor = :black, strokewidth = 1.3)
        @test_nowarn (save(tempname() * ".png", fig); true)
    end

    @testset "azimuthal/globular gallery projections keep finite graticule extents" begin
        # Inverting an interim/default camera rectangle can produce non-finite
        # geographic bounds for projections with a bounded domain (airy, aeqd,
        # apian, august, ...). Construction, layout and rendering must stay
        # finite instead of ranging a graticule over Inf/NaN.
        for dest in ("+proj=airy", "+proj=aeqd", "+proj=apian", "+proj=august")
            fig = Figure()
            ga = GeoAxis(fig[1, 1]; dest = dest, title = dest)
            hidedecorations!(ga; grid = false)
            @test_nowarn Makie.update_state_before_display!(fig)
            @test_nowarn (save(tempname() * ".png", fig); true)
        end
    end
end
