# Dense raster rendering benchmark: seam-clipped `heatmap!`/`surface!` meshes
# on a GeoAxis (the `_geo_grid_mesh` path in contoursplitting_geo.jl).
#
# Run with:
#   julia --project=. benchmark/raster.jl

using GeoMakie, CairoMakie, Makie

function summarize(name, f; runs = 3)
    times = Float64[]
    allocs = UInt[]
    for _ = 1:runs
        push!(times, @elapsed f())
        push!(allocs, @allocated f())
    end
    sort!(times)
    med = times[cld(length(times), 2)]
    println(
        rpad(name, 46),
        "min=",
        lpad(round(times[1]; digits = 4), 8),
        "  median=",
        lpad(round(med; digits = 4), 8),
        "  allocs=",
        lpad(round((sum(allocs) / length(allocs)) / 1024^2; digits = 2), 8),
        " MiB",
    )
    return
end

function raster_heatmap(n; dest = "+proj=moll +lon_0=180", size = (800, 600))
    fig = Figure(; size = size)
    ga = GeoAxis(fig[1, 1]; dest = dest)
    xs = range(-180, 180; length = n)
    ys = range(-90, 90; length = n)
    z = [sin(deg2rad(x)) * cos(deg2rad(y)) for x in xs, y in ys]
    heatmap!(ga, xs, ys, z)
    Makie.update_state_before_display!(fig)
    return fig
end

function raster_surface(n; dest = "+proj=moll +lon_0=180", size = (800, 600))
    fig = Figure(; size = size)
    ga = GeoAxis(fig[1, 1]; dest = dest)
    xs = range(-180, 180; length = n)
    ys = range(-90, 90; length = n)
    z = [sin(deg2rad(x)) * cos(deg2rad(y)) for x in xs, y in ys]
    surface!(ga, xs, ys, z; shading = Makie.NoShading)
    Makie.update_state_before_display!(fig)
    return fig
end

println("Dense raster benchmarks (CairoMakie, Julia ", VERSION, ")")
for n in (64, 128, 256)
    summarize("heatmap $(n)x$(n) moll+lon_0=180", () -> raster_heatmap(n))
    summarize("surface $(n)x$(n) moll+lon_0=180", () -> raster_surface(n))
end
summarize(
    "heatmap 256x256 ortho pole",
    () -> raster_heatmap(256; dest = "+proj=ortho +lat_0=90"),
)
