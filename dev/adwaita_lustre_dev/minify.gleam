import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import xmlm

const svg_namespace = "http://www.w3.org/2000/svg"

const xlink_namespace = "http://www.w3.org/1999/xlink"

const xml_namespace = "http://www.w3.org/XML/1998/namespace"

const junk_prefixes = [
  "font", "text-", "-inkscape", "marker", "solid-", "color-interpolation",
  "line-height", "letter-spacing", "word-spacing", "writing-mode", "direction",
  "dominant-baseline", "baseline-shift", "white-space", "shape-padding",
  "vector-effect", "color-rendering", "image-rendering", "enable-background",
  "overflow",
]

const dropped_elements = ["", "metadata", "title", "desc"]

type Property {
  Property(initial: String, inherited: Bool)
}

type Kind {
  Known
  Junk
  Other
}

type Tree {
  Tree(
    name: String,
    other: List(#(String, String)),
    props: List(#(String, String)),
    children: List(Tree),
  )
  Text(String)
}

pub fn svg(content: String) -> #(List(#(String, String)), String) {
  let keep_color = string.contains(content, "currentColor")
  let has_use = string.contains(content, "<use")
  let input =
    xmlm.from_string(content)
    |> xmlm.with_namespace_callback(fn(prefix) {
      case prefix {
        "xlink" -> Some(xlink_namespace)
        _ -> Some("unknown:" <> prefix)
      }
    })
  let #(root_other, root_children) = case
    xmlm.document_tree(
      input,
      fn(tag, children) { element(tag, children, keep_color, has_use) },
      fn(data) { [Text(data)] },
    )
  {
    Ok(#(_, [Tree(name: "svg", other:, props: [], children:)], _)) -> #(
      other,
      children,
    )
    Ok(_) -> panic as "Unexpected SVG root"
    Error(error) -> panic as xmlm.input_error_to_string(error)
  }
  let children = list.map(root_children, recolor(_, False))
  let children = case has_use {
    True -> children
    False ->
      list.map(children, prune(_, dict.from_list([#("fill", "currentColor")])))
  }
  let children = case uses_stroke(children) {
    True -> children
    False -> list.map(children, remove_stroke)
  }
  let used_ids = list.fold(children, set.new(), collect_references)
  let children = list.map(children, remove_unused_ids(_, used_ids))
  #(root_other, string.concat(list.map(children, render)))
}

fn element(
  tag: xmlm.Tag,
  children: List(List(Tree)),
  keep_color: Bool,
  has_use: Bool,
) -> List(Tree) {
  let name = case tag.name.uri {
    "" -> tag.name.local
    uri if uri == svg_namespace -> tag.name.local
    _ -> ""
  }
  case list.contains(dropped_elements, name) {
    True -> []
    False -> {
      let attributes = list.filter_map(tag.attributes, resolve_name)
      let #(other, props) = resolve(attributes, keep_color)
      let children =
        children
        |> list.flatten
        |> list.filter(fn(child) {
          case child {
            Text(text) -> string.trim(text) != ""
            Tree(..) -> True
          }
        })
      simplify(Tree(name:, other:, props:, children:), has_use)
    }
  }
}

fn resolve_name(attribute: xmlm.Attribute) -> Result(#(String, String), Nil) {
  let local = attribute.name.local
  case attribute.name.uri {
    "" -> Ok(#(local, attribute.value))
    uri if uri == svg_namespace -> Ok(#(local, attribute.value))
    uri if uri == xlink_namespace ->
      case local {
        "href" -> Ok(#("href", attribute.value))
        _ -> Ok(#("xlink:" <> local, attribute.value))
      }
    uri if uri == xml_namespace -> Ok(#("xml:" <> local, attribute.value))
    _ -> Error(Nil)
  }
}

fn property(name: String, keep_color: Bool) -> Result(Property, Nil) {
  case name {
    "fill" -> Ok(Property("#000", True))
    "fill-opacity" | "stroke-opacity" -> Ok(Property("1", True))
    "fill-rule" | "clip-rule" -> Ok(Property("nonzero", True))
    "stroke" | "stroke-dasharray" -> Ok(Property("none", True))
    "stroke-width" -> Ok(Property("1", True))
    "stroke-linecap" -> Ok(Property("butt", True))
    "stroke-linejoin" -> Ok(Property("miter", True))
    "stroke-miterlimit" -> Ok(Property("4", True))
    "stroke-dashoffset" -> Ok(Property("0", True))
    "visibility" -> Ok(Property("visible", True))
    "shape-rendering" -> Ok(Property("auto", True))
    "color" if keep_color -> Ok(Property("", True))
    "opacity" -> Ok(Property("1", False))
    "display" -> Ok(Property("inline", False))
    "clip-path" | "mask" | "filter" -> Ok(Property("none", False))
    "isolation" -> Ok(Property("auto", False))
    "mix-blend-mode" -> Ok(Property("normal", False))
    _ -> Error(Nil)
  }
}

fn classify(name: String, keep_color: Bool) -> Kind {
  case property(name, keep_color) {
    Ok(_) -> Known
    Error(Nil) ->
      case
        name == "color" || list.any(junk_prefixes, string.starts_with(name, _))
      {
        True -> Junk
        False -> Other
      }
  }
}

type Resolved {
  Resolved(
    other: List(#(String, String)),
    props: List(#(String, String)),
    style: List(String),
  )
}

fn resolve(
  attributes: List(#(String, String)),
  keep_color: Bool,
) -> #(List(#(String, String)), List(#(String, String))) {
  let #(styles, attributes) =
    list.partition(attributes, fn(attribute) { attribute.0 == "style" })
  let declarations = list.flat_map(styles, fn(style) { parse_style(style.1) })
  let entries =
    list.append(
      list.map(attributes, fn(attribute) { #(attribute, False) }),
      list.map(declarations, fn(declaration) { #(declaration, True) }),
    )
  let resolved =
    list.fold(entries, Resolved([], [], []), fn(resolved, entry) {
      let #(#(name, value), from_style) = entry
      case classify(name, keep_color), from_style {
        Known, _ ->
          Resolved(
            ..resolved,
            props: put(resolved.props, name, normalize_value(name, value)),
          )
        Junk, _ -> resolved
        Other, True ->
          Resolved(..resolved, style: [name <> ":" <> value, ..resolved.style])
        Other, False ->
          Resolved(..resolved, other: [#(name, value), ..resolved.other])
      }
    })
  let other = list.reverse(resolved.other)
  let other = case resolved.style {
    [] -> other
    style ->
      list.append(other, [#("style", string.join(list.reverse(style), ";"))])
  }
  #(other, resolved.props)
}

fn parse_style(style: String) -> List(#(String, String)) {
  style
  |> string.split(";")
  |> list.filter_map(fn(declaration) {
    use #(name, value) <- result.try(string.split_once(declaration, ":"))
    case string.trim(name), string.trim(value) {
      "", _ | _, "" -> Error(Nil)
      name, value -> Ok(#(name, value))
    }
  })
}

fn put(
  props: List(#(String, String)),
  name: String,
  value: String,
) -> List(#(String, String)) {
  case list.key_find(props, name) {
    Ok(_) ->
      list.map(props, fn(prop) {
        case prop.0 == name {
          True -> #(name, value)
          False -> prop
        }
      })
    Error(Nil) -> list.append(props, [#(name, value)])
  }
}

fn normalize_value(name: String, value: String) -> String {
  let value = string.trim(value)
  case name {
    "fill" | "stroke" | "color" -> normalize_color(value)
    _ -> value
  }
}

fn normalize_color(color: String) -> String {
  let color = string.lowercase(color)
  case color {
    "black" -> "#000"
    "white" -> "#fff"
    _ ->
      case string.to_graphemes(color) {
        ["#", a1, a2, b1, b2, c1, c2] if a1 == a2 && b1 == b2 && c1 == c2 ->
          "#" <> a1 <> b1 <> c1
        _ -> color
      }
  }
}

fn simplify(tree: Tree, has_use: Bool) -> List(Tree) {
  case tree {
    Tree(name: "g", children: [], ..) | Tree(name: "defs", children: [], ..) -> []
    Tree(name: "g", other: [], props: [], children:) -> children
    Tree(name: "g", other: [], props:, children: [Tree(..) as child]) ->
      case has_use || !list.all(props, is_inherited) {
        True -> [tree]
        False -> [Tree(..child, props: merge_props(props, child.props))]
      }
    _ -> [tree]
  }
}

fn is_inherited(prop: #(String, String)) -> Bool {
  case property(prop.0, True) {
    Ok(definition) -> definition.inherited
    Error(Nil) -> False
  }
}

fn merge_props(
  parent: List(#(String, String)),
  child: List(#(String, String)),
) -> List(#(String, String)) {
  list.fold(parent, child, fn(merged, prop) {
    case list.key_find(merged, prop.0) {
      Ok(_) -> merged
      Error(Nil) -> list.append(merged, [prop])
    }
  })
}

fn prune(tree: Tree, inherited: Dict(String, String)) -> Tree {
  case tree {
    Text(_) -> tree
    Tree(props:, children:, ..) -> {
      let #(kept, inherited) =
        list.fold(props, #([], inherited), fn(state, prop) {
          let #(kept, inherited) = state
          let assert Ok(definition) = property(prop.0, True)
          let parent_value = case definition.inherited {
            True ->
              dict.get(inherited, prop.0) |> result.unwrap(definition.initial)
            False -> definition.initial
          }
          case prop.1 == parent_value, definition.inherited {
            True, _ -> state
            False, True -> #(
              [prop, ..kept],
              dict.insert(inherited, prop.0, prop.1),
            )
            False, False -> #([prop, ..kept], inherited)
          }
        })
      Tree(
        ..tree,
        props: list.reverse(kept),
        children: list.map(children, prune(_, inherited)),
      )
    }
  }
}

fn recolor(tree: Tree, in_mask: Bool) -> Tree {
  case tree {
    Text(_) -> tree
    Tree(name:, props:, children:, ..) -> {
      let in_mask = in_mask || name == "mask" || name == "filter"
      let props = case in_mask {
        True -> props
        False -> list.map(props, recolor_prop)
      }
      let props = case name, list.key_find(props, "fill") {
        "mask", Error(Nil) -> list.append(props, [#("fill", "#000")])
        _, _ -> props
      }
      Tree(..tree, props:, children: list.map(children, recolor(_, in_mask)))
    }
  }
}

fn recolor_prop(prop: #(String, String)) -> #(String, String) {
  case prop.0, prop.1 {
    "fill", "none" | "stroke", "none" -> prop
    "fill", value | "stroke", value ->
      case string.starts_with(value, "url(") {
        True -> prop
        False -> #(prop.0, "currentColor")
      }
    _, _ -> prop
  }
}

fn uses_stroke(trees: List(Tree)) -> Bool {
  list.any(trees, fn(tree) {
    case tree {
      Text(_) -> False
      Tree(props:, children:, ..) ->
        list.any(props, fn(prop) { prop.0 == "stroke" && prop.1 != "none" })
        || uses_stroke(children)
    }
  })
}

fn remove_stroke(tree: Tree) -> Tree {
  case tree {
    Text(_) -> tree
    Tree(props:, children:, ..) ->
      Tree(
        ..tree,
        props: list.filter(props, fn(prop) {
          !string.starts_with(prop.0, "stroke")
        }),
        children: list.map(children, remove_stroke),
      )
  }
}

fn collect_references(references: Set(String), tree: Tree) -> Set(String) {
  case tree {
    Text(_) -> references
    Tree(other:, props:, children:, ..) ->
      list.fold(
        children,
        list.fold(
          list.append(other, props),
          references,
          fn(references, attribute) {
            list.fold(
              attribute_references(attribute.0, attribute.1),
              references,
              set.insert,
            )
          },
        ),
        collect_references,
      )
  }
}

fn attribute_references(name: String, value: String) -> List(String) {
  case name {
    "href" | "xlink:href" ->
      case string.starts_with(value, "#") {
        True -> [string.drop_start(value, 1)]
        False -> []
      }
    _ ->
      value
      |> string.split("url(#")
      |> list.drop(1)
      |> list.filter_map(fn(part) {
        string.split_once(part, ")") |> result.map(fn(pair) { pair.0 })
      })
  }
}

fn remove_unused_ids(tree: Tree, used_ids: Set(String)) -> Tree {
  case tree {
    Text(_) -> tree
    Tree(other:, children:, ..) ->
      Tree(
        ..tree,
        other: list.filter(other, fn(attribute) {
          attribute.0 != "id" || set.contains(used_ids, attribute.1)
        }),
        children: list.map(children, remove_unused_ids(_, used_ids)),
      )
  }
}

fn render(tree: Tree) -> String {
  case tree {
    Text(text) -> escape(text)
    Tree(name:, other:, props:, children:) -> {
      let attributes =
        list.append(list.map(other, minify_attribute), props)
        |> list.map(fn(attribute) {
          " " <> attribute.0 <> "=\"" <> escape_attribute(attribute.1) <> "\""
        })
        |> string.concat
      case children {
        [] -> "<" <> name <> attributes <> "/>"
        _ ->
          "<"
          <> name
          <> attributes
          <> ">"
          <> string.concat(list.map(children, render))
          <> "</"
          <> name
          <> ">"
      }
    }
  }
}

fn minify_attribute(attribute: #(String, String)) -> #(String, String) {
  case attribute.0 {
    "d" -> #("d", minify_path(attribute.1))
    _ -> #(attribute.0, collapse_whitespace(attribute.1))
  }
}

fn collapse_whitespace(value: String) -> String {
  value
  |> string.replace("\n", " ")
  |> string.replace("\r", " ")
  |> string.replace("\t", " ")
  |> string.split(" ")
  |> list.filter(fn(part) { part != "" })
  |> string.join(" ")
}

fn minify_path(data: String) -> String {
  minify_path_loop(string.to_graphemes(data), "", False, [])
}

fn minify_path_loop(
  characters: List(String),
  previous: String,
  separated: Bool,
  output: List(String),
) -> String {
  case characters {
    [] -> output |> list.reverse |> string.concat
    [character, ..rest] ->
      case list.contains([" ", "\n", "\r", "\t", ","], character) {
        True -> minify_path_loop(rest, previous, True, output)
        False -> {
          let needs_space =
            separated
            && previous != ""
            && !is_command(previous)
            && !is_command(character)
            && character != "-"
          let output = case needs_space {
            True -> [character, " ", ..output]
            False -> [character, ..output]
          }
          minify_path_loop(rest, character, False, output)
        }
      }
  }
}

fn is_command(character: String) -> Bool {
  string.contains("MmLlHhVvCcSsQqTtAaZz", character)
}

fn escape(text: String) -> String {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
}

fn escape_attribute(value: String) -> String {
  value
  |> escape
  |> string.replace("\"", "&quot;")
}
