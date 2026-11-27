//// The library of saved drawings. A drawing is a name and the source of its draw
//// function.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Library {
  Library(selected: String, drawings: List(#(String, String)))
}

const library_key = "animator.library"

// One JSON header records the selection and UTF-8 lengths. The drawing sources
// follow it verbatim, so newlines, quotes, and incomplete code are kept as typed.
pub fn save_library(library: Library) -> Nil {
  let header =
    json.object([
      #("selected", json.string(library.selected)),
      #(
        "drawings",
        json.array(library.drawings, fn(drawing) {
          let #(name, source) = drawing
          json.object([
            #("name", json.string(name)),
            #("bytes", json.int(string.byte_size(source))),
          ])
        }),
      ),
    ])
    |> json.to_string
  let sources = list.map(library.drawings, fn(drawing) { drawing.1 })
  storage_set(library_key, string.concat([header, "\n", ..sources]))
}

pub fn load_library() -> Result(Library, Nil) {
  use stored <- result.try(storage_get(library_key))
  use #(header, sources) <- result.try(string.split_once(stored, "\n"))
  use #(selected, entries) <- result.try(
    json.parse(header, header_decoder()) |> result.replace_error(Nil),
  )
  use drawings <- result.try(
    read_sources(entries, bit_array.from_string(sources), []),
  )
  case list.key_find(drawings, selected) {
    Ok(_) if selected != "" -> Ok(Library(selected:, drawings:))
    _ -> Error(Nil)
  }
}

fn header_decoder() -> decode.Decoder(#(String, List(#(String, Int)))) {
  use selected <- decode.field("selected", decode.string)
  use entries <- decode.field(
    "drawings",
    decode.list(of: {
      use name <- decode.field("name", decode.string)
      use bytes <- decode.field("bytes", decode.int)
      decode.success(#(name, bytes))
    }),
  )
  decode.success(#(selected, entries))
}

fn read_sources(
  entries: List(#(String, Int)),
  sources: BitArray,
  drawings: List(#(String, String)),
) -> Result(List(#(String, String)), Nil) {
  case entries {
    [] if sources == <<>> -> Ok(list.reverse(drawings))
    [#(name, bytes), ..rest] if bytes >= 0 ->
      case sources {
        <<source:bytes-size(bytes), remaining:bytes>> -> {
          use code <- result.try(bit_array.to_string(source))
          read_sources(rest, remaining, [#(name, code), ..drawings])
        }
        _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

// ── localStorage (data_ffi.mjs) ───────────────────────────────────────────────

/// The string stored in localStorage under key, or an Error if there isn't one.
@external(javascript, "./data_ffi.mjs", "storageGet")
pub fn storage_get(key: String) -> Result(String, Nil)

/// Store value in localStorage under key, replacing anything already there. If that
/// isn't possible, this logs the reason to the browser console.
@external(javascript, "./data_ffi.mjs", "storageSet")
pub fn storage_set(key: String, value: String) -> Nil

// ── The new-drawing prompt (data_ffi.mjs) ─────────────────────────────────────

/// Prompt the user to name a new drawing; "" (empty string) means they
/// cancelled or left it blank.
@external(javascript, "./data_ffi.mjs", "promptDrawingName")
pub fn prompt_drawing_name() -> String
