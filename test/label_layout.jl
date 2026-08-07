using GeoMakie, CairoMakie, GeometryBasics, Test
const G = GeoMakie

@testset "Label placement modes and deterministic layout" begin
    @testset "inline vs outside vs auto" begin
        boundary = G.Point2d[
            G.Point2d(0, 0),
            G.Point2d(500, 0),
            G.Point2d(500, 500),
            G.Point2d(0, 500),
            G.Point2d(0, 0),
        ]
        curves = G.GraticuleCurve[
            G.GraticuleCurve(
                0.0,
                :meridian,
                G.Point2d[G.Point2d(0, -10), G.Point2d(0, 510)],
                G.Point2d[G.Point2d(100, -10), G.Point2d(100, 510)],
            ),
            G.GraticuleCurve(
                30.0,
                :meridian,
                G.Point2d[G.Point2d(30, -10), G.Point2d(30, 510)],
                G.Point2d[G.Point2d(300, -10), G.Point2d(300, 510)],
            ),
        ]
        inline = G.place_graticule_labels(
            curves,
            [0.0, 30.0],
            :meridian,
            boundary;
            side = :bottom,
            fonts = nothing,
            placement = :inline,
        )
        @test length(inline) == 2
        @test all(c -> c.placement_class === :inline && c.interior, inline)

        outside = G.place_graticule_labels(
            curves,
            [0.0, 30.0],
            :meridian,
            boundary;
            side = :bottom,
            fonts = nothing,
            placement = :outside,
        )
        @test length(outside) == 2
        @test all(c -> c.placement_class === :outside && !c.interior, outside)

        auto = G.place_graticule_labels(
            curves,
            [0.0, 30.0],
            :meridian,
            boundary;
            side = :bottom,
            fonts = nothing,
            placement = :auto,
        )
        @test auto == outside
    end

    @testset "local improvement keeps shifted labels" begin
        font = Makie.defaultfont()
        c1 = G.label_candidate(
            1,
            G.Point2d(100, 0),
            "100°",
            font,
            16.0,
            0.0,
            (:center, :center),
            0,
            0.0;
            side = :bottom,
            boundary_tangent = G.Point2d(1, 0),
            placement_class = :outside,
        )
        c2 = G.label_candidate(
            2,
            G.Point2d(110, 0),
            "110°",
            font,
            16.0,
            0.0,
            (:center, :center),
            0,
            0.0;
            side = :bottom,
            boundary_tangent = G.Point2d(1, 0),
            placement_class = :outside,
        )
        @test G._candidate_overlaps(c2, [c1])
        accepted = [c1]
        G._local_improve!(accepted, [c2])
        @test length(accepted) == 2
        @test accepted[2].position_px[1] > accepted[1].position_px[1] + 20
    end

    @testset "polar inline labels are stable and interior" begin
        center = G.Point2d(250.0, 250.0)
        r = 200.0
        boundary = G.Point2d[
            center .+ G.Point2d(r * cos(2π * i / 360), r * sin(2π * i / 360)) for i = 0:360
        ]
        parallels = G.GraticuleCurve[
            G.GraticuleCurve(
                lat,
                :parallel,
                G.Point2d[G.Point2d(-180, lat), G.Point2d(180, lat)],
                G.Point2d[
                    center .+ G.Point2d(100 * cosd(lon), 100 * sind(lon)) for
                    lon = -180.0:10.0:180.0
                ],
            ) for lat in (60.0, 70.0, 80.0)
        ]
        a = G.place_graticule_labels(
            parallels,
            [60.0, 70.0, 80.0],
            :parallel,
            boundary;
            side = :left,
            fonts = nothing,
            placement = :inline,
        )
        b = G.place_graticule_labels(
            parallels,
            [60.0, 70.0, 80.0],
            :parallel,
            boundary;
            side = :left,
            fonts = nothing,
            placement = :inline,
        )
        @test a == b
        @test all(c -> c.placement_class === :inline && c.interior, a)
    end

    @testset "GeoAxis accepts placement attributes" begin
        fig = Figure()
        ga = GeoAxis(
            fig[1, 1];
            dest = "+proj=eqearth",
            xticklabelplacement = :inline,
            yticklabelplacement = :inline,
        )
        Makie.update_state_before_display!(fig)
        @test ga.xticklabelplacement[] === :inline
        @test ga.yticklabelplacement[] === :inline
        @test (save(tempname() * ".png", fig); true)
    end
end
