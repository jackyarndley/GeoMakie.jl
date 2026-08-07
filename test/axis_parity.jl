using GeoMakie, CairoMakie, GeometryBasics, Test
const G = GeoMakie

@testset "GeoAxis axis parity surface" begin
    fig = Figure()
    ga = GeoAxis(
        fig[1, 1];
        dest = "+proj=eqearth",
        title = "t",
        subtitle = "s",
        xlabel = "x",
        ylabel = "y",
    )

    # Documented attributes exist and are settable.
    for attr in (
        :title,
        :subtitle,
        :xlabel,
        :ylabel,
        :xticklabelplacement,
        :yticklabelplacement,
        :spinevisible,
        :spinewidth,
        :spinecolor,
        :xgridvisible,
        :xgridwidth,
        :xgridcolor,
        :xticksvisible,
        :xtickwidth,
        :xticksize,
        :xtickcolor,
        :xticklabelsvisible,
        :xticklabelpad,
        :xticklabelrotation,
    )
        @test hasproperty(ga, attr)
    end
    @test ga.title[] == "t"
    @test ga.xlabel[] == "x"
    @test ga.xticklabelplacement[] === :outside

    # Limit and interaction APIs exist.
    for f in (
        Makie.xlims!,
        Makie.ylims!,
        Makie.limits!,
        Makie.tightlimits!,
        Makie.autolimits!,
        Makie.reset_limits!,
    )
        @test f isa Function
    end
    for f in (Makie.linkxaxes!, Makie.linkyaxes!, Makie.linkaxes!)
        @test f isa Function
    end
    @test unlinkaxes! isa Function

    Makie.update_state_before_display!(fig)
    @test ga.scene.viewport[] isa GeometryBasics.HyperRectangle{2,Int}
end
