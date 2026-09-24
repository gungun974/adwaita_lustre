import adwaita_lustre_dev/minify
import gleam/list
import gleam/string
import simplifile

const suffix = "-symbolic.svg"

const kept_attributes = ["width", "height", "viewBox"]

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
    list.filter(root_attributes, fn(attribute) {
      list.contains(kept_attributes, attribute.0)
    })
  #([#("fill", "currentColor"), ..attributes], inner_html)
}
