using GeoMakie, GeometryBasics, LinearAlgebra, Test
const G = GeoMakie
const _LL = "+proj=longlat +datum=WGS84"

@testset "Projection boundary strategies" begin
    @testset "strategy selection" begin
        @test G.boundary_strategy(G.geoprojection("+proj=eqearth", _LL)) isa G.AnalyticBoundary
        @test G.boundary_strategy(G.geoprojection("+proj=ortho", _LL)) isa G.CircularBoundary
        @test G.boundary_strategy(G.geoprojection("+proj=igh", _LL)) isa G.SphericalPolygonBoundary
        @test G.boundary_strategy(G.geoprojection("+proj=guyou", _LL)) isa G.AdaptiveBoundary
        @test G.boundary_strategy(G.geoprojection("+proj=tpeqd +lat_1=60 +lat_2=65", _LL)) isa
            G.AdaptiveBoundary
    end

    @testset "adaptive fallback for projections without analytic boundaries" begin
        gp = G.geoprojection("+proj=guyou", _LL)
        pts = G.boundary_points(gp)
        @test length(pts) > 50
        @test all(p -> isfinite(p[1]) && isfinite(p[2]), pts)
    end

    @testset "component identity and NaN-separated segments" begin
        gp = G.geoprojection("+proj=igh", _LL)
        comps = G.boundary_components(gp)
        @test length(comps) >= 1
        segs = G.boundary_segments(gp)
        @test any(isnan, segs)
        flat = G.boundary_points(gp)
        @test !isempty(flat)
        @test all(p -> isfinite(p[1]) && isfinite(p[2]), flat)
        @test length(flat) <= length(segs)
    end

    @testset "circular boundary" begin
        gp = G.geoprojection("+proj=ortho +lat_0=90", _LL)
        pts = G.boundary_points(gp)
        @test length(pts) > 100
        cx = sum(p -> p[1], pts) / length(pts)
        cy = sum(p -> p[2], pts) / length(pts)
        radii = [hypot(p[1] - cx, p[2] - cy) for p in pts]
        @test maximum(radii) / minimum(radii) < 1.2
    end

    @testset "analytic boundary" begin
        gp = G.geoprojection("+proj=eqearth", _LL)
        pts = G.boundary_points(gp)
        @test length(pts) > 100
        @test all(p -> isfinite(p[1]) && isfinite(p[2]), pts)
    end
end
