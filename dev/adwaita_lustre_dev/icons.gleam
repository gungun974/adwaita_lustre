import adwaita_lustre_dev/minify
import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import simplifile

const suffix = "-symbolic.svg"

pub type Icon {
  Icon(
    directory: String,
    name: String,
    attributes: List(#(String, String)),
    inner_html: String,
  )
}

pub fn load(icons_dir: String) -> List(Icon) {
  let assert Ok(files) = simplifile.get_files(icons_dir)
  files
  |> list.filter(string.ends_with(_, suffix))
  |> list.sort(string.compare)
  |> list.map(fn(path) { read_icon(icons_dir, path) })
}

fn read_icon(icons_dir: String, path: String) -> Icon {
  let assert Ok(content) = simplifile.read(path)
  let assert Ok(relative) = string.split_once(path, icons_dir <> "/")
  let segments = string.split(relative.1, "/")
  let assert Ok(file) = list.last(segments)
  let directory =
    segments
    |> list.take(list.length(segments) - 1)
    |> string.join("/")
  let #(attributes, inner_html) = split_svg(content)
  Icon(
    directory:,
    name: string.drop_end(file, string.length(suffix)),
    attributes:,
    inner_html:,
  )
}

fn split_svg(content: String) -> #(List(#(String, String)), String) {
  let #(root_attributes, inner_html) = minify.svg(content)
  let attributes =
    root_attributes
    |> with_view_box
    |> list.filter(fn(attribute) { attribute.0 == "viewBox" })
  #([#("fill", "currentColor"), ..attributes], inner_html)
}

fn with_view_box(
  attributes: List(#(String, String)),
) -> List(#(String, String)) {
  case
    list.key_find(attributes, "viewBox"),
    list.key_find(attributes, "width"),
    list.key_find(attributes, "height")
  {
    Error(Nil), Ok(width), Ok(height) ->
      case is_number(width) && is_number(height) {
        True ->
          list.append(attributes, [
            #(
              "viewBox",
              "0 0 " <> remove_unit(width) <> " " <> remove_unit(height),
            ),
          ])
        False -> attributes
      }
    _, _, _ -> attributes
  }
}

fn remove_unit(value: String) -> String {
  string.replace(value, "px", "")
}

fn is_number(value: String) -> Bool {
  let value = remove_unit(value)
  result.is_ok(int.parse(value)) || result.is_ok(float.parse(value))
}
