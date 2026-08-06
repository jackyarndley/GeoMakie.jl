# GeoAxis / Makie Axis parity

This page classifies the Makie `Axis` surface against `GeoAxis`.

## Supported

- Titles and subtitles (`title`, `subtitle`, fonts, sizes, colors, gaps,
  visibility, alignment).
- Axis labels (`xlabel`, `ylabel`, fonts, sizes, colors, padding, visibility).
- Grid lines (`xgridcolor`, `xgridwidth`, `xgridstyle`, visibility).
- Spine (`spinevisible`, `spinewidth`, `spinecolor`).
- Tick marks (`xticksvisible`, `xtickwidth`, `xticksize`, `xtickcolor`,
  `xtickalign`, minor-tick attributes reserved).
- Tick labels (`xticklabelsvisible`, `xticklabelalign`, `xticklabelpad`,
  `xticklabelrotation`, `xticklabelspace`, fonts, sizes, colors).
- Label placement (`xticklabelplacement`/`yticklabelplacement`:
  `:outside`, `:inline`, `:auto`).
- `hidedecorations!`, `hidexdecorations!`, `hideydecorations!`.
- Limits: `xlims!`, `ylims!`, `limits!`, `tightlimits!`, `autolimits!`,
  `reset_limits!`, `geolimits!`, `projected_limits!`.
- Geographic linking: `linkxaxes!`, `linkyaxes!`, `linkaxes!`,
  `unlinkaxes!`.
- Legends, rectangle zoom, scroll zoom, drag pan, and layout protrusions.
- Themes, fonts, `DataAspect`/`AxisAspect`, and reversed y axes.

## Not meaningful for geographic axes

- Reversing the x axis via `xlims!(west > east)` — on a `GeoAxis` that denotes a
  wrapped longitude interval, not a reversed axis.

## Deferred

- Minor ticks and minor grid rendering (attributes exist; rendering is
  follow-up work).
- `backgroundcolor` (GeoAxis background fill).
- `linkaxes!` between projected (non-geographic) source CRSs.
- Full `Axis`-style inline tick-label collision with neighboring layout blocks.

## Unsupported (clear errors)

- Linking `GeoAxis` instances whose source CRSs are not both geographic raises
  `ArgumentError` instead of silently misinterpreting coordinates.
