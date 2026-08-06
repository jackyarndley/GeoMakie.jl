using GeoMakie, CairoMakie, GeometryBasics, Test
const G = GeoMakie

@testset "GeoAxis caching and interaction quality" begin
    @testset "bounded eviction" begin
        c = G.BoundedDict{Int, Int}(3)
        for i in 1:10
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
end
