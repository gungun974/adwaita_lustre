import adwaita_lustre_dev/download
import adwaita_lustre_dev/generate
import adwaita_lustre_dev/icons
import adwaita_lustre_dev/log
import gleam/int
import gleam/io
import gleam/list

pub fn main() {
  let source_path =
    download.download(
      id: "adwaita-icon-theme",
      version: "40.1",
      url: "https://gitlab.gnome.org/GNOME/adwaita-icon-theme/-/archive/40.1/adwaita-icon-theme-40.1.tar.gz",
      root: "adwaita-icon-theme-40.1",
      sha256: "6a13f97bf12eb24b00a72335c37324ac51556050115d7b3fdcdb83f081039d28",
    )

  let library_path =
    download.download(
      id: "icon-library",
      version: "0.0.8",
      url: "https://gitlab.gnome.org/World/design/icon-library/-/archive/0.0.8/icon-library-0.0.8.tar.gz",
      root: "icon-library-0.0.8",
      sha256: "7aaebac60d615138971327a064f7a39ca19ea69e78c27b5fee04de0be76d135c",
    )

  let icons =
    log.step("Icons loading", fn() {
      let adwaita_icons = icons.load(source_path <> "/Adwaita/scalable")
      let library_icons =
        icons.load(library_path <> "/data/resources/icon-dev-kit")
      let known = list.map(adwaita_icons, fn(icon) { icon.name })
      list.append(
        adwaita_icons,
        list.filter(library_icons, fn(icon) { !list.contains(known, icon.name) }),
      )
    })

  let count = log.step("Code generation", fn() { generate.generate(icons) })
  io.println("Generated " <> int.to_string(count) <> " icons")
}
