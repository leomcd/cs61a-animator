//// Convert each shape into a list of points called a RenderPath.

import shape.{type Path, type Point, Line}

/// One path as canvas.mjs setDrawing consumes it (field by field): the
/// polyline, stroke colour/width, and the start and end times (in tenths of a second)
/// between which the reveal runs — so the renderer's clock needs no shape
/// knowledge.
pub type RenderPath {
  RenderPath(
    points: List(Point),
    thickness: Float,
    color: String,
    start: Float,
    end: Float,
  )
}

pub type VisualEffects {
  VisualEffects(
    kaleidoscope: Bool,
    sectors: Int,
    mirror: Bool,
    stagger_ms: Int,
    neon: Bool,
    // How long the glow lasts, in tenths of a second.
    trail_length: Int,
    keep_ink: Bool,
    particles: Bool,
  )
}

// ── The canvas (canvas.mjs) ───────────────────────────────────────────────────

/// Replace the drawing being animated in the page's
/// `<canvas id="animation-canvas">` element. If that element doesn't appear within
/// about 10 seconds, this logs an error to the browser console. This keeps the
/// current time, so a drawing that replaces a finished one appears complete. To
/// animate it from the start, also call reset_clock.
@external(javascript, "./canvas.mjs", "setDrawing")
pub fn set_drawing(paths: List(RenderPath)) -> Nil

/// Change the canvas effects at the current animation time.
@external(javascript, "./canvas.mjs", "setVisualEffects")
pub fn set_visual_effects(effects: VisualEffects) -> Nil

/// Set the animation's speed, as a multiple of its normal speed: 1.0 is normal and
/// is where it starts, 0.0 pauses, and a negative rate plays it backward.
@external(javascript, "./canvas.mjs", "setSpeed")
pub fn set_speed(rate: Float) -> Nil

/// Wrap playback at the end of a finite animation, in either direction.
@external(javascript, "./canvas.mjs", "setLooping")
pub fn set_looping(looping: Bool) -> Nil

/// Start playback at a nonzero rate. Restart or replay starts at the end when
/// playing backward and at the beginning when playing forward.
@external(javascript, "./canvas.mjs", "startPlayback")
pub fn start_playback(rate: Float, restart: Bool) -> Nil

/// Report whether the clock can advance at the current rate, including when it
/// reaches either end of the drawing.
@external(javascript, "./canvas.mjs", "watchPlayback")
pub fn watch_playback(on_change: fn(Bool) -> Nil) -> Nil

/// Jump the animation back to its start, where the canvas is empty.
@external(javascript, "./canvas.mjs", "resetClock")
pub fn reset_clock() -> Nil

pub fn render_path(path: Path, color: String) -> RenderPath {
  case path.shape {
    Line(a, b) ->
      RenderPath([a, b], path.thickness, color, path.start, path.end)
  }
}
