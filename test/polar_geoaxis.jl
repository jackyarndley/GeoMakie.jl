using GeoMakie, CairoMakie, GeometryBasics, LinearAlgebra, Test
using Makie.GridLayoutBase
const G = GeoMakie
const _LL = "+proj=longlat +datum=WGS84"

@testset "Unified polar support via GeoAxis" begin
    @testset "GeoPolarAxis is removed" begin
        @test !isdefined(Main, :GeoPolarAxis)
        @test !isdefined(G, :GeoPolarAxis)
    end

    polar_cases = [
        (
            "north stereographic",
            "+proj=stere +lat_0=90 +lon_0=0 +datum=WGS84",
            (-180.0, 180.0, 60.0, 90.0),
        ),
        (
            "south stereographic",
            "+proj=stere +lat_0=-90 +lon_0=0 +datum=WGS84",
            (-180.0, 180.0, -90.0, -60.0),
        ),
        (
            "north Lambert azimuthal",
            "+proj=laea +lat_0=90 +lon_0=30 +datum=WGS84",
            (-180.0, 180.0, 45.0, 90.0),
        ),
        (
            "north orthographic",
            "+proj=ortho +lat_0=90 +lon_0=0 +datum=WGS84",
            (-180.0, 180.0, -90.0, 90.0),
        ),
    ]

    for (name, dest, lims) in polar_cases
        @testset "$name" begin
            t = G.create_transform(dest, _LL)
            @test G.clip_strategy(t) isa G.CircleClip

            b = filter(p -> isfinite(p[1]) && isfinite(p[2]), G.boundary_points(dest))
            @test length(b) > 100
            cx = sum(p -> p[1], b) / length(b)
            cy = sum(p -> p[2], b) / length(b)
            radii = [hypot(p[1] - cx, p[2] - cy) for p in b]
            # Polar azimuthal/perspective boundaries are (near-)circular.
            @test maximum(radii) / minimum(radii) < 1.2
            span = 2 * maximum(radii)

            # Graticules are finite and meridians do not create seam-spanning
            # segments.
            gp = G.geoprojection(dest, _LL)
            extent = (lims[1], lims[2], lims[3], lims[4])
            curves = G.generate_graticule(gp, -180.0:60.0:180.0, -60.0:30.0:90.0, extent)
            finitepts = count(
                p -> isfinite(p[1]) && isfinite(p[2]),
                reduce(vcat, [c.projected_geometry for c in curves]; init = Point2d[]),
            )
            @test finitepts > 0
            for c in curves
                c.kind == :meridian || continue
                pts = c.projected_geometry
                for i = 2:length(pts)
                    a = pts[i-1]
                    b = pts[i]
                    (
                        isfinite(a[1]) &&
                        isfinite(a[2]) &&
                        isfinite(b[1]) &&
                        isfinite(b[2])
                    ) || continue
                    @test hypot(b[1] - a[1], b[2] - a[2]) < 0.5 * span + 1.0
                end
            end

            # Land is clipped inside the projected boundary.
            proj = G._projector(gp)
            sp = G.split_geometry(G.land(), dest)
            @test !isempty(sp)
            outside = 0
            tot = 0
            for poly in sp, q in GeometryBasics.coordinates(poly.exterior)
                xy = proj(q[1], q[2])
                (isfinite(xy[1]) && isfinite(xy[2])) || continue
                tot += 1
                hypot(xy[1] - cx, xy[2] - cy) > maximum(radii) + 1.0e-6 && (outside += 1)
            end
            @test tot > 0
            @test outside < 0.05 * tot
        end
    end

    @testset "polar cap rendering, layout and hiding" begin
        fig = Figure()
        ga = GeoAxis(
            fig[1, 1];
            dest = "+proj=stere +lat_0=90 +lon_0=0 +datum=WGS84",
            limits = (-180.0, 180.0, 60.0, 90.0),
        )
        lines!(ga, [-170.0, 170.0], [65.0, 75.0])
        Makie.update_state_before_display!(fig)
        p = ga.layoutobservables.protrusions[]
        @test all(isfinite, (p.left, p.right, p.bottom, p.top))
        @test all(≥(0.0), (p.left, p.right, p.bottom, p.top))

        Makie.hidedecorations!(ga)
        Makie.update_state_before_display!(fig)
        @test ga.layoutobservables.protrusions[] ==
              GridLayoutBase.RectSides{Float32}(0.0f0, 0.0f0, 0.0f0, 0.0f0)

        @test (save(tempname() * ".png", fig); true)
    end

    @testset "longitude labels around a circular polar boundary" begin
        center = Point2d(250.0, 250.0)
        r = 200.0
        boundary = Point2d[
            center .+ Point2d(r * cos(2π * i / 360), r * sin(2π * i / 360)) for i = 0:360
        ]
        lons = -180.0:45.0:135.0
        curves = G.GraticuleCurve[
            G.GraticuleCurve(
                lon,
                :meridian,
                Point2d[Point2d(lon, 60), Point2d(lon, 90)],
                Point2d[center, center .+ Point2d(r*cosd(lon), r*sind(lon))],
            ) for lon in lons
        ]
        cands = G.place_graticule_labels(
            curves,
            lons,
            :meridian,
            boundary;
            side = :auto,
            fonts = nothing,
        )
        @test length(cands) >= 4
        # Exterior labels: further from the centre than the boundary radius.
        @test all(c -> norm(c.position_px .- center) > r, cands)
        # No accepted labels overlap.
        for i = 1:length(cands), j = (i+1):length(cands)
            a = cands[i].bbox_px
            b = cands[j].bbox_px
            xov = max(
                0.0,
                min(a.origin[1] + a.widths[1], b.origin[1] + b.widths[1]) -
                max(a.origin[1], b.origin[1]),
            )
            yov = max(
                0.0,
                min(a.origin[2] + a.widths[2], b.origin[2] + b.widths[2]) -
                max(a.origin[2], b.origin[2]),
            )
            @test !(xov > 2.0 && yov > 2.0)
        end
    end

    @testset "latitude labels on polar parallels" begin
        center = Point2d(250.0, 250.0)
        r = 200.0
        boundary = Point2d[
            center .+ Point2d(r * cos(2π * i / 360), r * sin(2π * i / 360)) for i = 0:360
        ]
        parallel = G.GraticuleCurve(
            70.0,
            :parallel,
            Point2d[Point2d(-180, 70), Point2d(180, 70)],
            Point2d[
                center .+ Point2d(100 * cosd(lon), 100 * sind(lon)) for
                lon = -180.0:10.0:180.0
            ],
        )
        cands = G.place_graticule_labels(
            [parallel],
            [70.0],
            :parallel,
            boundary;
            side = :left,
            fonts = nothing,
        )
        @test length(cands) == 1
        @test cands[1].interior
        @test cands[1].position_px[1] < center[1]      # left-side placement
        @test norm(cands[1].position_px .- center) < r # stays inside the map
    end

    @testset "reactive projection and limit changes on one GeoAxis" begin
        fig = Figure()
        ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
        Makie.update_state_before_display!(fig)
        @test ga.transform_func[] isa Proj.Transformation

        # cylindrical -> north-polar stereographic on the same axis
        ga.dest[] = "+proj=stere +lat_0=90 +lon_0=0 +datum=WGS84"
        Makie.update_state_before_display!(fig)
        @test ga.transform_func[] isa Proj.Transformation
        @test ga.scene.viewport[] isa GeometryBasics.HyperRectangle{2,Int}

        # global -> regional polar cap limits
        xlims!(ga, -180, 180)
        ylims!(ga, 60, 90)
        Makie.update_state_before_display!(fig)
        fl = ga.finallimits[]
        @test isfinite(minimum(fl)[1]) && isfinite(maximum(fl)[2])
        reset_limits!(ga)
        autolimits!(ga)
        @test (save(tempname() * ".png", fig); true)
    end
end
