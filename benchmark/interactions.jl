# Lightweight GeoAxis interaction/caching benchmarks.
#
# Run with:
#   julia --project=. benchmark/interactions.jl
#
# Reports minimum, median and mean wall time plus allocations over `runs`
# repetitions. The test suite deliberately does not depend on these timings.

using GeoMakie, CairoMakie

function summarize(name, f; runs = 5)
    times = Float64[]
    allocs = UInt[]
    for _ = 1:runs
        push!(times, @elapsed f())
        push!(allocs, @allocated f())
    end
    sort!(times)
    med = times[cld(length(times), 2)]
    println(
        rpad(name, 42),
        "min=",
        lpad(round(times[1]; digits = 4), 8),
        "  median=",
        lpad(round(med; digits = 4), 8),
        "  mean=",
        lpad(round(sum(times) / length(times); digits = 4), 8),
        "  allocs=",
        lpad(round((sum(allocs) / length(allocs)) / 1024; digits = 1), 8),
        " KiB",
    )
    return
end

function cold_axis()
    fig = Figure()
    return GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
end

function warm_axis()
    fig = Figure()
    ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
    Makie.update_state_before_display!(fig)
    return ga
end

function graticule(dest)
    gp = GeoMakie.geoprojection(dest, "+proj=longlat +datum=WGS84")
    GeoMakie.generate_graticule(
        gp,
        -180.0:30.0:180.0,
        -90.0:30.0:90.0,
        (-180.0, 180.0, -90.0, 90.0),
    )
end

function labels(dest)
    gp = GeoMakie.geoprojection(dest, "+proj=longlat +datum=WGS84")
    b = GeoMakie.boundary_points(gp)
    curves = GeoMakie.generate_graticule(
        gp,
        -180.0:30.0:180.0,
        -90.0:30.0:90.0,
        (-180.0, 180.0, -90.0, 90.0),
    )
    xmin = minimum(p -> p[1], b)
    xmax = maximum(p -> p[1], b)
    ymin = minimum(p -> p[2], b)
    ymax = maximum(p -> p[2], b)
    s = 400.0 / max(xmax - xmin, ymax - ymin)
    bpix = [GeoMakie.Point2d((p[1] - xmin) * s + 50, (p[2] - ymin) * s + 50) for p in b]
    cpix = [
        GeoMakie.GraticuleCurve(
            c.coordinate,
            c.kind,
            c.geographic_geometry,
            [
                isnan(p[1]) ? p :
                GeoMakie.Point2d((p[1] - xmin) * s + 50, (p[2] - ymin) * s + 50) for
                p in c.projected_geometry
            ],
        ) for c in curves
    ]
    GeoMakie.place_graticule_labels(
        cpix,
        -180.0:30.0:180.0,
        :meridian,
        bpix;
        side = :auto,
        fonts = nothing,
    )
end

function main()
    println("GeoAxis interaction/caching benchmarks (runs are warm after the first)")
    summarize("cold GeoAxis construction", cold_axis)
    summarize("warm GeoAxis construction + update", warm_axis)
    summarize("global eqearth graticule", () -> graticule("+proj=eqearth"))
    summarize(
        "polar stereographic graticule",
        () -> graticule("+proj=stere +lat_0=90 +lon_0=0"),
    )
    summarize("global eqearth label placement", () -> labels("+proj=eqearth"))

    summarize(
        "figure resize",
        () -> begin
            fig = Figure()
            ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
            resize_to_layout!(fig)
            Makie.update_state_before_display!(fig)
            ga
        end;
        runs = 3,
    )
    summarize(
        "drag pan (targetlimits update)",
        () -> begin
            fig = Figure()
            ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
            Makie.update_state_before_display!(fig)
            ga.targetlimits[] = Makie.BBox(-1.0e7, 1.0e7, -5.0e6, 5.0e6)
            ga
        end;
        runs = 3,
    )
    summarize(
        "scroll zoom (targetlimits update)",
        () -> begin
            fig = Figure()
            ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
            Makie.update_state_before_display!(fig)
            ga.targetlimits[] = Makie.BBox(-0.5e7, 0.5e7, -2.5e6, 2.5e6)
            ga
        end;
        runs = 3,
    )
    summarize(
        "dest change cylindrical -> polar",
        () -> begin
            fig = Figure()
            ga = GeoAxis(fig[1, 1]; dest = "+proj=eqearth")
            ga.dest[] = "+proj=stere +lat_0=90 +lon_0=0"
            Makie.update_state_before_display!(fig)
            ga
        end;
        runs = 3,
    )
    summarize(
        "nine-panel GeoAxis figure",
        () -> begin
            fig = Figure(size = (900, 900))
            for i = 1:9
                GeoAxis(fig[fldmod1(i, 3)...]; dest = "+proj=eqearth")
            end
            resize_to_layout!(fig)
            Makie.update_state_before_display!(fig)
            fig
        end;
        runs = 3,
    )
end

main()
