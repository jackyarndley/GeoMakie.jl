using GeoMakie, CairoMakie, GeometryBasics, Test
const G = GeoMakie
const _LL = "+proj=longlat +datum=WGS84"

@testset "GeoAxis v2 internals" begin
    @testset "ProjectionTraits" begin
        for (dest, family, cliptype) in [
                ("+proj=eqearth", :seamed, G.AntimeridianClip),
                ("+proj=ortho", :azimuthal_or_perspective, G.CircleClip),
                ("+proj=igh", :interrupted, G.PolygonClip),
                ("+proj=tpeqd +lat_1=60 +lat_2=65", :continuous, G.NoClip),
            ]
            gp = G.geoprojection(dest, _LL)
            @test gp.traits.family == family
            @test gp.traits.clip_strategy isa cliptype
            @test gp.forward isa Proj.Transformation
            @test gp.inverse isa Proj.Transformation
        end
        gp = G.geoprojection("+proj=merc", _LL)
        @test gp.traits.seam_longitudes == Float64[-180.0, 180.0]
        @test gp.traits.singular_latitudes == Float64[-85.0, 85.0]
        @test gp.traits.longitude_periodic
    end

    @testset "GeoProjection roundtrip" begin
        gp = G.geoprojection("+proj=eqearth", _LL)
        proj = G._projector(gp)
        xy = proj(10.0, 20.0)
        ll = gp.inverse((xy[1], xy[2]))
        @test isapprox(ll[1], 10.0; atol = 1.0e-6)
        @test isapprox(ll[2], 20.0; atol = 1.0e-6)
    end

    @testset "GeoViewport" begin
        gp = G.geoprojection("+proj=eqearth", _LL)
        boundary = G.boundary_points(gp)
        vp = G.GeoViewport(gp, Rect2{Float64}(-2.0e7, -1.0e7, 4.0e7, 2.0e7), boundary)
        @test vp.geographic_extent[1] < vp.geographic_extent[2]
        @test vp.geographic_extent[3] < vp.geographic_extent[4]
        @test !isempty(vp.projected_boundary)
        @test !isempty(vp.visible_boundary)
    end

    @testset "Graticule engine" begin
        gp = G.geoprojection("+proj=eqearth", _LL)
        curves = G.generate_graticule(gp, [-180.0, 0.0, 180.0], [-60.0, 0.0, 60.0],
            (-180.0, 180.0, -85.0, 85.0))
        @test length(curves) == 6
        finitepts = count(p -> isfinite(p[1]) && isfinite(p[2]),
            reduce(vcat, [c.projected_geometry for c in curves]; init = Point2d[]))
        @test finitepts > 0
        boundary = G.boundary_points(gp)
        ix = G.graticule_boundary_intersections(curves[1], boundary)
        @test !isempty(ix)
        @test all(t -> isfinite(t[1][1]) && isfinite(t[1][2]), ix)
    end

    @testset "Boundary-aware labels" begin
        # A simple pixel rectangle: labels must sit outside the boundary and use
        # the outward normal, alignment, and measured text boxes.
        boundary = Point2d[Point2d(0, 0), Point2d(500, 0), Point2d(500, 500),
            Point2d(0, 500), Point2d(0, 0)]
        curves = G.GraticuleCurve[
            G.GraticuleCurve(0.0, :meridian,
                Point2d[Point2d(0, -85), Point2d(0, 85)],
                Point2d[Point2d(100, -10), Point2d(100, 510)]),
            G.GraticuleCurve(30.0, :meridian,
                Point2d[Point2d(30, -85), Point2d(30, 85)],
                Point2d[Point2d(300, -10), Point2d(300, 510)]),
        ]
        cands = G.place_graticule_labels(curves, [0.0, 30.0], :meridian, boundary;
            side = :bottom, fonts = nothing)
        @test length(cands) == 2
        @test all(c -> c.position_px[2] < 0, cands)
        @test all(c -> c.alignment[2] == :top, cands)
        # no overlap between the two labels
        a, b = cands
        xoverlap = min(a.bbox_px.origin[1] + a.bbox_px.widths[1],
                b.bbox_px.origin[1] + b.bbox_px.widths[1]) -
            max(a.bbox_px.origin[1], b.bbox_px.origin[1])
        @test xoverlap <= 2
    end

    @testset "Decoration extents" begin
        ext = G.DecorationExtents()
        G.add_extent!(ext, :bottom, 30.0)
        G.add_extent!(ext, :bottom, 10.0)
        @test ext.bottom == 30.0
        @test G.same_extents(ext, G.DecorationExtents(0.0, 0.0, 30.0, 0.0))
        @test !G.same_extents(ext, G.DecorationExtents(0.0, 0.0, 31.0, 0.0); tol = 0.5)
    end

    @testset "GeoTicks interface" begin
        @test Makie.get_tickvalues(G.GeoTicks(6), -180.0, 180.0) isa AbstractVector
        spaced = Makie.get_tickvalues(G.GeoTicks(; spacing = 30), -180.0, 180.0)
        @test length(spaced) == 13
        @test all(diff(spaced) .≈ 30.0)
        vals = Makie.get_tickvalues(G.GeoTicks(; values = -180:30:180), -90.0, 90.0)
        @test vals == collect(-90.0:30.0:90.0)
        @test Makie.get_tickvalues(G.GeoTicks(; values = -180:30:180), -180.0, 180.0) isa AbstractVector
    end

    @testset "Layout convergence" begin
        fig = Figure()
        ga = GeoAxis(fig[1, 1])
        lines!(ga, [-170.0, 170.0], [10.0, 20.0])
        resize_to_layout!(fig)
        Makie.update_state_before_display!(fig)
        p1 = ga.layoutobservables.protrusions[]
        Makie.update_state_before_display!(fig)
        p2 = ga.layoutobservables.protrusions[]
        @test p1 == p2
        @test all(isfinite, (p1.left, p1.right, p1.bottom, p1.top))
        @test all(≥(0.0), (p1.left, p1.right, p1.bottom, p1.top))
    end
end
