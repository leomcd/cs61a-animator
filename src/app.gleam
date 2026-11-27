//// Animator -- an application for program-generated drawings.

import builtins
import data
import drawing
import editor
import errors
import examples
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import parser
import render.{type RenderPath, type VisualEffects, VisualEffects}
import shape.{type Path}

/// Your app's public address, once you've deployed it in Problem 13, such as
/// "https://your-username.github.io/animator/".
pub const public_url = "https://leomcd.github.io/cs61a-animator/"

/// Set to True if you would like your app's URL included in the course gallery.
pub const include_app_in_gallery = False

/// A link to your video from Problem 14, which anyone with the link can watch.
pub const video_url = ""

/// Set to True if you would like your video included in the course gallery.
pub const include_video_in_gallery = False

const default_code =
  "fn draw(shape_slider: Int) -> List(Path) {\n  [Path(Line(Point(0, 0), Point(100, 100)), 0, 10, 2)]\n}\n"

// ── Model ──────────────────────────────────────────────────────────────────────

pub type Model {
  Model(
    drawing_name: String,
    drawings: List(#(String, String)),
    // The code in the editor.
    source: String,
    shape_slider: Int,
    speed: Float,
    last_playback_speed: Float,
    playing: Bool,
    looping: Bool,
    visual_effects: VisualEffects,
    // Whether the code editor is shown.
    code_open: Bool,
    code_error: Option(String),
  )
}

pub type Msg {
  SetCode(String)
  SelectDrawing(String)
  NewDrawingNamed(String)
  SetShapeSlider(String)
  SetSpeed(String)
  TogglePlayback
  RestartPlayback
  PlaybackChanged(Bool)
  SetLooping(Bool)
  SetKaleidoscope(Bool)
  SetSectors(String)
  SetMirror(Bool)
  SetStagger(String)
  SetNeon(Bool)
  SetTrailLength(String)
  SetKeepInk(Bool)
  SetParticles(Bool)

  // Layout controls
  ToggleCode
}

// ── Init ───────────────────────────────────────────────────────────────────────

pub fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  let assert [#(first_example, _), ..] = examples.all
  let data.Library(selected: name, drawings:) =
    data.load_library()
    |> result.unwrap(data.Library(first_example, examples.all))
  let assert Ok(source) = list.key_find(drawings, name)
  let #(model, drawing_effect) =
    mount_drawing(Model(
      drawing_name: name,
      drawings:,
      source:,
      shape_slider: 10,
      speed: 1.0,
      last_playback_speed: 1.0,
      playing: True,
      looping: False,
      visual_effects: VisualEffects(
        kaleidoscope: False,
        sectors: 6,
        mirror: True,
        stagger_ms: 60,
        neon: False,
        trail_length: 6,
        keep_ink: True,
        particles: False,
      ),
      code_open: True,
      code_error: None,
    ))
  let watch_playback =
    effect.from(fn(dispatch) {
      render.watch_playback(fn(playing) { dispatch(PlaybackChanged(playing)) })
    })
  #(model, effect.batch([drawing_effect, watch_playback]))
}

// Parse and evaluate a draw function at the given shape-slider value, returning
// the rendered paths on success, or a human-readable message on failure.
fn run_source(shape_slider: Int, source: String) -> Result(List(Path), String) {
  case parser.parse_program(source, builtins.global_frame()) {
    Error(msg) -> Error(msg)
    Ok(program) ->
      drawing.try_draw(shape_slider, program)
      // Convert Error(EvalError) to Error(String) with a useful error message.
      |> result.map_error(errors.error_message)
  }
}

// ── Update ─────────────────────────────────────────────────────────────────────

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ToggleCode -> #(Model(..model, code_open: !model.code_open), effect.none())
    SetCode(text) -> {
      let drawings = list.key_set(model.drawings, model.drawing_name, text)
      redraw(Model(..model, drawings:, source: text), restart_clock: False)
      |> save_library
    }

    SelectDrawing("") -> #(
      model,
      effect.from(fn(dispatch) {
        dispatch(NewDrawingNamed(data.prompt_drawing_name()))
      }),
    )

    SelectDrawing(name) ->
      case list.key_find(model.drawings, name) {
        Ok(source) -> switch_drawing(model, name, source)
        Error(Nil) -> #(model, effect.none())
      }

    NewDrawingNamed(name) ->
      case string.trim(name) {
        "" -> #(model, effect.none())
        name ->
          case list.key_find(model.drawings, name) {
            Ok(source) -> switch_drawing(model, name, source)
            Error(Nil) -> {
              let drawings = list.key_set(model.drawings, name, default_code)
              switch_drawing(Model(..model, drawings:), name, default_code)
            }
          }
      }

    SetShapeSlider(value) ->
      case int.parse(value) {
        Ok(shape_slider) ->
          redraw(Model(..model, shape_slider:), restart_clock: False)
        Error(Nil) -> #(model, effect.none())
      }

    SetSpeed(value) -> {
      // Range inputs send whole numbers without a decimal point.
      let rate =
        float.parse(value)
        |> result.lazy_or(fn() { int.parse(value) |> result.map(int.to_float) })
      case rate {
        Ok(speed) -> set_playback_speed(model, speed)
        Error(Nil) -> #(model, effect.none())
      }
    }

    TogglePlayback ->
      case model.playing {
        True -> set_playback_speed(model, 0.0)
        False -> start_playback(model, restart: False)
      }

    RestartPlayback -> start_playback(model, restart: True)

    PlaybackChanged(playing) -> #(Model(..model, playing:), effect.none())

    SetLooping(looping) -> #(
      Model(..model, looping:),
      effect.from(fn(_) { render.set_looping(looping) }),
    )

    SetKaleidoscope(kaleidoscope) ->
      set_visual_effects(
        model,
        VisualEffects(..model.visual_effects, kaleidoscope:),
      )
    SetSectors(value) ->
      case int.parse(value) {
        Ok(count) -> {
          let sectors = int.clamp(count, 2, 12)
          set_visual_effects(
            model,
            VisualEffects(..model.visual_effects, sectors:),
          )
        }
        Error(Nil) -> #(model, effect.none())
      }
    SetMirror(mirror) ->
      set_visual_effects(model, VisualEffects(..model.visual_effects, mirror:))
    SetStagger(value) ->
      case int.parse(value) {
        Ok(delay) -> {
          let stagger_ms = int.clamp(delay, 0, 200)
          set_visual_effects(
            model,
            VisualEffects(..model.visual_effects, stagger_ms:),
          )
        }
        Error(Nil) -> #(model, effect.none())
      }
    SetNeon(neon) ->
      set_visual_effects(model, VisualEffects(..model.visual_effects, neon:))
    SetKeepInk(keep_ink) ->
      set_visual_effects(
        model,
        VisualEffects(..model.visual_effects, keep_ink:),
      )
    SetParticles(particles) ->
      set_visual_effects(
        model,
        VisualEffects(..model.visual_effects, particles:),
      )
    SetTrailLength(value) ->
      case int.parse(value) {
        Ok(length) -> {
          let trail_length = int.clamp(length, 1, 20)
          set_visual_effects(
            model,
            VisualEffects(..model.visual_effects, trail_length:),
          )
        }
        Error(Nil) -> #(model, effect.none())
      }
  }
}

fn set_visual_effects(
  model: Model,
  visual_effects: VisualEffects,
) -> #(Model, Effect(Msg)) {
  #(
    Model(..model, visual_effects:),
    effect.from(fn(_) { render.set_visual_effects(visual_effects) }),
  )
}

fn set_playback_speed(model: Model, speed: Float) -> #(Model, Effect(Msg)) {
  let last_playback_speed = case speed {
    0.0 -> model.last_playback_speed
    _ -> speed
  }
  #(
    Model(..model, speed:, last_playback_speed:),
    effect.from(fn(_) { render.set_speed(speed) }),
  )
}

fn start_playback(
  model: Model,
  restart restart: Bool,
) -> #(Model, Effect(Msg)) {
  let speed = model.last_playback_speed
  #(
    Model(..model, speed:),
    effect.from(fn(_) { render.start_playback(speed, restart) }),
  )
}

fn switch_drawing(
  model: Model,
  name: String,
  source: String,
) -> #(Model, Effect(Msg)) {
  case name == model.drawing_name {
    True -> #(model, effect.none())
    False ->
      mount_drawing(Model(..model, drawing_name: name, source:)) |> save_library
  }
}

fn save_library(update: #(Model, Effect(Msg))) -> #(Model, Effect(Msg)) {
  let #(model, other_effect) = update
  let save =
    effect.from(fn(_) {
      data.save_library(data.Library(model.drawing_name, model.drawings))
    })
  #(model, effect.batch([other_effect, save]))
}

fn mount_drawing(model: Model) -> #(Model, Effect(Msg)) {
  let #(model, drawing_effect) = redraw(model, restart_clock: True)
  #(model, effect.batch([editor.mount(model.source, SetCode), drawing_effect]))
}

fn redraw(model: Model, restart_clock restart: Bool) -> #(Model, Effect(Msg)) {
  case run_source(model.shape_slider, model.source) {
    Ok(paths) -> {
      let render_paths = list.map(paths, render.render_path(_, "#d4c5a0"))
      #(Model(..model, code_error: None), draw_paths(render_paths, restart))
    }
    Error(msg) -> #(Model(..model, code_error: Some(msg)), case restart {
      True -> draw_paths([], True)
      False -> effect.none()
    })
  }
}

fn draw_paths(paths: List(RenderPath), restart: Bool) -> Effect(Msg) {
  effect.from(fn(_) {
    case restart {
      True -> render.reset_clock()
      False -> Nil
    }
    render.set_drawing(paths)
  })
}

// ── View ──────────────────────────────────────────────────────────────────
//
// Two side-by-side panes: the code editor on the left and its rendered output on
// the right. The code column can be hidden to expand the right pane.

pub fn view(model: Model) -> Element(Msg) {
  let app_class = case model.code_open {
    True -> "app"
    False -> "app code-hidden"
  }
  // The code column still exists even when hidden (CSS collapses it) so the
  // mounted CodeMirror editor keeps its state across show/hide.
  html.div([attr.class(app_class)], [
    html.div([attr.class("code-col")], [
      editor.view_panel(ToggleCode),
    ]),
    view_anim(model),
  ])
}

fn view_anim(model: Model) -> Element(Msg) {
  let error = case model.code_error {
    None -> element.none()
    Some(message) -> html.p([], [html.text(message)])
  }
  html.div([attr.class("animation-pane")], [
    html.div([attr.class("canvas-area")], [
      view_reveal_code(model),
      html.canvas([attr.id("animation-canvas"), attr.class("canvas")]),
      html.div([attr.class("code-status"), attr.role("status")], [error]),
    ]),
    view_visual_effects(model.visual_effects),
    view_controls(model),
  ])
}

fn view_visual_effects(effects: VisualEffects) -> Element(Msg) {
  let neon_controls = case effects.neon {
    False -> element.none()
    True -> {
      let value = int.to_string(effects.trail_length)
      let seconds = float.to_string(int.to_float(effects.trail_length) /. 10.0)
      html.div([attr.class("neon-controls")], [
        view_slider("trail-length", "Trail length", seconds <> " s", [
          attr.min("1"),
          attr.max("20"),
          attr.step("1"),
          attr.value(value),
          attr.aria_valuetext(seconds <> " seconds"),
          event.on_input(SetTrailLength),
        ]),
        effect_checkbox("Keep ink", effects.keep_ink, SetKeepInk),
      ])
    }
  }
  html.div(
    [
      attr.class("effect-controls"),
      attr.role("group"),
      attr.aria_label("Drawing effects"),
    ],
    [
      effect_checkbox("Kaleidoscope", effects.kaleidoscope, SetKaleidoscope),
      effect_checkbox("Neon trails", effects.neon, SetNeon),
      effect_checkbox("Ink splatter", effects.particles, SetParticles),
      view_kaleidoscope_options(effects),
      neon_controls,
    ],
  )
}

fn view_kaleidoscope_options(effects: VisualEffects) -> Element(Msg) {
  case effects.kaleidoscope {
    False -> element.none()
    True -> {
      let sectors = int.to_string(effects.sectors)
      let stagger = int.to_string(effects.stagger_ms)
      html.div(
        [
          attr.class("kaleidoscope-controls"),
          attr.role("group"),
          attr.aria_label("Kaleidoscope settings"),
        ],
        [
          view_slider("kaleidoscope-sectors", "Sectors", sectors, [
            attr.min("2"),
            attr.max("12"),
            attr.step("1"),
            attr.value(sectors),
            event.on_input(SetSectors),
          ]),
          view_slider("kaleidoscope-stagger", "Stagger", stagger <> " ms", [
            attr.min("0"),
            attr.max("200"),
            attr.step("10"),
            attr.value(stagger),
            attr.aria_valuetext(stagger <> " milliseconds"),
            event.on_input(SetStagger),
          ]),
          effect_checkbox("Mirror", effects.mirror, SetMirror),
        ],
      )
    }
  }
}

fn effect_checkbox(
  label: String,
  checked: Bool,
  on_change: fn(Bool) -> Msg,
) -> Element(Msg) {
  html.label([attr.class("effect-toggle")], [
    html.input([
      attr.type_("checkbox"),
      attr.checked(checked),
      event.on_check(on_change),
    ]),
    html.text(label),
  ])
}

fn view_drawing_select(model: Model) -> Element(Msg) {
  let drawing_options =
    list.map(model.drawings, fn(drawing) {
      let #(name, _) = drawing
      html.option(
        [attr.value(name), attr.selected(name == model.drawing_name)],
        name,
      )
    })
  let new_drawing = html.option([attr.value("")], "New drawing…")
  html.div([attr.class("animation-control")], [
    html.label([attr.for("drawing-select")], [html.text("Drawing")]),
    html.select(
      [
        attr.id("drawing-select"),
        attr.attribute("data-test-id", "drawing-select"),
        attr.value(model.drawing_name),
        event.on_change(SelectDrawing),
      ],
      list.append(drawing_options, [new_drawing]),
    ),
  ])
}

fn view_controls(model: Model) -> Element(Msg) {
  let shape_value = int.to_string(model.shape_slider)
  let speed_value = float.to_string(model.speed)
  html.div([attr.class("animation-controls")], [
    view_drawing_select(model),
    view_slider("shape-slider", "Shape", shape_value, [
      attr.attribute("data-test-id", "shape-slider"),
      attr.min("0"),
      attr.max("100"),
      attr.step("1"),
      attr.value(shape_value),
      event.on_input(SetShapeSlider),
    ]),
    view_slider("speed-slider", "Speed", speed_value <> "×", [
      attr.attribute("data-test-id", "speed-slider"),
      attr.min("-2"),
      attr.max("2"),
      attr.step("0.1"),
      attr.value(speed_value),
      event.on_input(SetSpeed),
    ]),
    view_playback(model.playing, model.looping),
  ])
}

fn view_playback(playing: Bool, looping: Bool) -> Element(Msg) {
  let label = case playing {
    True -> "Pause"
    False -> "Play"
  }
  html.div(
    [
      attr.class("playback-buttons"),
      attr.role("group"),
      attr.aria_label("Playback"),
    ],
    [
      html.button(
        [
          attr.class("icon-btn"),
          attr.type_("button"),
          event.on_click(TogglePlayback),
        ],
        [html.text(label)],
      ),
      html.button(
        [
          attr.class("icon-btn"),
          attr.type_("button"),
          event.on_click(RestartPlayback),
        ],
        [html.text("Restart")],
      ),
      effect_checkbox("Loop", looping, SetLooping),
    ],
  )
}

fn view_slider(
  id: String,
  label: String,
  value: String,
  input_attrs: List(attr.Attribute(Msg)),
) -> Element(Msg) {
  html.div([attr.class("animation-control")], [
    html.label([attr.for(id)], [html.text(label)]),
    html.span([attr.class("slider-value"), attr.aria_hidden(True)], [
      html.text(value),
    ]),
    html.input([attr.id(id), attr.type_("range"), ..input_attrs]),
  ])
}

// The button that brings the code column back, overlaid on the top-left of the
// right pane. Nothing is rendered while the column is already showing (its own
// header holds the button that hides it).
fn view_reveal_code(model: Model) -> Element(Msg) {
  case model.code_open {
    True -> element.none()
    False ->
      html.button(
        [
          attr.class("icon-btn reveal-code"),
          attr.attribute("title", "Show code"),
          event.on_click(ToggleCode),
        ],
        [html.text("⟩")],
      )
  }
}

// ── Main ───────────────────────────────────────────────────────────────────────

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
