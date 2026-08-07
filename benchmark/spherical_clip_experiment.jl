# GeometryOps spherical clipping experiment (review item: try GO's spherical
# Sutherland–Hormann/Foster–Hormann path against GeoMakie's d3-style
# `_clip_against_polygon` for a narrow convex case).
#
# Status on GeometryOps 0.1.42: NOT usable — constructing
# `GO.FosterHormannClipping(GO.Spherical(), ...)` throws a method ambiguity
# between the generic and the Spherical-specialized constructors, so
# `GO.intersection(GO.Spherical(), a, b)` cannot be called at all. The parity
# test below (`test/sphere_clip.jl` "GeometryOps spherical clipping parity")
# is `@test_broken` until an upstream GeometryOps release resolves the
# ambiguity (JuliaGeo/GeometryOps.jl#457); it will then start validating the
# narrow convex-parity contract.

using GeoMakie
const G = GeoMakie
const GO = G.GO
const GI = G.GI

# Convex spherical quad clip (lon/lat degrees) and convex subject overlapping it.
clip = [(0.0, 0.0), (30.0, 0.0), (30.0, 30.0), (0.0, 30.0)]
subj = [(10.0, 10.0), (40.0, 10.0), (40.0, 40.0), (10.0, 40.0)]
pa = GI.Polygon([GI.LinearRing([GI.Point(p) for p in clip])])
pb = GI.Polygon([GI.LinearRing([GI.Point(p) for p in subj])])

go_ok = try
    alg = GO.FosterHormannClipping(GO.Spherical())
    out = GO.intersection(alg, pa, pb; target = GI.PolygonTrait())
    println("GO spherical intersection: ", length(out), " polygon(s)")
    true
catch e
    println("GO spherical intersection unavailable: ", sprint(showerror, e))
    false
end

# GeoMakie's own path on the same input (a small PolygonClip of the quad).
function geomakie_clip()
    gp = G.geoprojection("+proj=longlat +datum=WGS84", "+proj=longlat +datum=WGS84")
    # Clip the subject against the spherical quad with a PolygonClip.
    clipdeg = [G.Point2d(p[1], p[2]) for p in clip]
    pc = G.PolygonClip([clipdeg])
    polys = G._split_polygon(pc, G._poly_rings(pb), G._projector(gp.forward), 1.0)
    return polys
end

ours = geomakie_clip()
println("GeoMakie clip: ", length(ours), " polygon(s)")
println("parity check: ", go_ok ? "compare above" : "blocked by GO method ambiguity")
