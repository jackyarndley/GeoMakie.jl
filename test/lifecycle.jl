using GeoMakie, CairoMakie, GeometryBasics, Test
const G = GeoMakie
const _IS_GL = lowercase(get(ENV, "GEOMAKIE_TEST_BACKEND", "cairo")) == "gl"

@testset "Seam-aware plot lifecycle" begin
    # The returned handles are proper composite recipes: hiding/deleting them
    # affects their rendered children in every backend, and no hidden originals
    # or scene siblings are left behind.
    fig = Figure(size = (700, 600))
    ga = GeoAxis(fig[1, 1]; dest = "+proj=moll +lon_0=180")
    Makie.xlims!(ga, -180.0, 180.0)
    Makie.ylims!(ga, -90.0, 90.0)
    land = G.land()

    snapshot() = begin
        Makie.update_state_before_display!(fig)
        p = tempname() * ".png"
        save(p, fig)
        return read(p)
    end

    child_visible(p) = [c.visible[] for c in p.plots]

    cases = [
        ("poly", () -> poly!(ga, land[1:20]; color = (:gray70, 0.55))),
        (
            "line",
            () ->
                lines!(ga, [-160.0, 160.0], [10.0, 40.0]; color = :red, linewidth = 5),
        ),
        (
            "contour",
            () -> contour!(
                ga,
                -180:20:180,
                -90:20:90,
                [sin(deg2rad(x)) * cos(deg2rad(y)) for x = -180:20:180, y = -90:20:90],
            ),
        ),
        (
            "contourf",
            () -> contourf!(
                ga,
                -180:20:180,
                -90:20:90,
                [sin(deg2rad(x)) * cos(deg2rad(y)) for x = -180:20:180, y = -90:20:90],
            ),
        ),
        (
            "surface",
            () -> surface!(
                ga,
                -180:30:180,
                -90:30:90,
                [sin(deg2rad(x)) * cos(deg2rad(y)) for x = -180:30:180, y = -90:30:90];
                shading = Makie.NoShading,
            ),
        ),
        (
            "heatmap",
            () -> heatmap!(
                ga,
                -180:20:180,
                -90:20:90,
                [sin(deg2rad(x)) * cos(deg2rad(y)) for x = -180:20:180, y = -90:20:90],
            ),
        ),
    ]

    for (name, makeplot) in cases
        @testset "$name" begin
            base = snapshot()
            p = makeplot()
            shown = snapshot()
            @test !isempty(p.plots)
            if _IS_GL
                # Structural lifecycle checks (byte-exact rendering is not
                # stable across GL frames): hiding the returned plot hides its
                # children, showing restores them, deleting removes the handle.
                p.visible = false
                Makie.update_state_before_display!(fig)
                @test all(==(false), child_visible(p))
                p.visible = true
                Makie.update_state_before_display!(fig)
                # The frozen original child stays hidden; the rendered (last)
                # child follows the returned plot.
                @test p.plots[end].visible[]
                @test any(==(true), child_visible(p))
            else
                @test shown != base
                p.visible = false
                @test snapshot() == base
                p.visible = true
                @test snapshot() == shown
            end
            delete!(ga, p)
            @test snapshot() == base
            @test !any(x -> x === p, ga.scene.plots)
        end
    end
end
