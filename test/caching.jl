using GeoMakie, CairoMakie, GeometryBasics, Test
const G = GeoMakie
const _LL = "+proj=longlat +datum=WGS84"

@testset "GeoAxis caching and interaction quality" begin
    @testset "bounded eviction" begin
        c = G.BoundedDict{Int,Int}(3)
        for i = 1:10
            G.getcache!(c, i, () -> i)
        end
        @test length(c.data) <= 3
        @test length(c.order) <= 3
        @test length(c.data) == length(c.order)
    end

    @testset "text metrics are cached" begin
        bb1 = G.cached_text_bbox("10°", Makie.defaultfont(), 16.0)
        bb2 = G.cached_text_bbox("10°", Makie.defaultfont(), 16.0)
        @test bb1 === bb2
        @test length(G._TEXT_METRICS_CACHE.data) <= G._TEXT_METRICS_CACHE.maxsize
    end

    @testset "per-axis caches are populated and stable" begin
        fig = Figure()
        ga = GeoAxis(fig[1, 1]; dest = "+proj=moll")
        Makie.update_state_before_display!(fig)
        b1 = length(ga.cache.boundary.data)
        g1 = length(ga.cache.graticules.data)
        l1 = length(ga.cache.labels.data)
        @test b1 >= 1
        @test g1 >= 1
        @test l1 >= 1

        # A second update with unchanged state must hit the caches.
        Makie.update_state_before_display!(fig)
        @test length(ga.cache.boundary.data) == b1
        @test length(ga.cache.graticules.data) == g1
        @test length(ga.cache.labels.data) == l1

        # Interactive quality uses a separate (coarser) graticule entry.
        ga.interaction_active[] = true
        Makie.update_state_before_display!(fig)
        g2 = length(ga.cache.graticules.data)
        @test g2 >= g1

        # Returning to final quality reuses the final-quality entry.
        ga.interaction_active[] = false
        Makie.update_state_before_display!(fig)
        @test length(ga.cache.graticules.data) == g2

        G.clear_cache!(ga.cache)
        @test isempty(ga.cache.boundary.data)
        @test isempty(ga.cache.graticules.data)
        @test isempty(ga.cache.labels.data)
    end

    @testset "boundary cache stores the semantic ProjectionBoundary" begin
        fig = Figure()
        ga = GeoAxis(fig[1, 1]; dest = "+proj=igh")
        Makie.update_state_before_display!(fig)
        obj = first(values(ga.cache.boundary.data))
        @test obj isa G.ProjectionBoundary
        pts = G.boundary_points(obj)
        segs = G.boundary_segments(obj)
        @test !isempty(pts)
        @test all(p -> isfinite(p[1]) && isfinite(p[2]), pts)
        @test any(isnan, segs)
        # Points and segments are views of the same stored object: the cache
        # never holds one flattened representation that could poison the other.
        @test length(segs) >= length(pts)
    end

    @testset "graticule cache keys use tick values, not counts" begin
        cache = G.BoundedDict{
            Tuple{
                Any,
                Any,
                NTuple{4,Float64},
                Tuple{Vararg{Float64}},
                Tuple{Vararg{Float64}},
                Float64,
            },
            Vector{Int},
        }(
            4,
        )
        extent = (-180.0, 180.0, -90.0, 90.0)
        key1 = ("+proj=eqearth", _LL, extent, (0.0, 30.0), (0.0, 60.0), 1.0)
        key2 = ("+proj=eqearth", _LL, extent, (10.0, 40.0), (15.0, 45.0), 1.0)
        @test key1 != key2
        G.getcache!(cache, key1, () -> [1])
        G.getcache!(cache, key2, () -> [2])
        @test length(cache.data) == 2
        @test cache.data[key1] == [1]
        @test cache.data[key2] == [2]
    end

    @testset "projection cache is canonical and bounded" begin
        n0 = length(G._GEO_PROJECTION_CACHE)
        G.geoprojection("+proj=eqearth +lon_0=123.456", _LL)
        @test length(G._GEO_PROJECTION_CACHE) == n0 + 1
        G.geoprojection("+proj=eqearth +lon_0=123.456", _LL)
        @test length(G._GEO_PROJECTION_CACHE) == n0 + 1
        # An Observable CRS unwraps to the same canonical key.
        G.geoprojection(Makie.Observable("+proj=eqearth +lon_0=123.456"), _LL)
        @test length(G._GEO_PROJECTION_CACHE) == n0 + 1
        @test G._GEO_PROJECTION_CACHE_MAX >= 1
        @test length(G._GEO_PROJECTION_CACHE) <= G._GEO_PROJECTION_CACHE_MAX
    end
end
