import adwaita_lustre_dev/download
import adwaita_lustre_dev/generate
import adwaita_lustre_dev/icons
import adwaita_lustre_dev/log
import gleam/int
import gleam/io

pub fn main() {
  let source_path =
    download.download(
      id: "adwaita-icon-theme",
      version: "51.0",
      url: "https://gitlab.gnome.org/GNOME/adwaita-icon-theme/-/archive/51.0/adwaita-icon-theme-51.0.tar.gz",
      root: "adwaita-icon-theme-51.0",
      sha256: "adda5270c67ecdeb9604d24202fd8558b193379f9a9488179591cd4cdd99593b",
    )

  let icons =
    log.step("Icons loading", fn() {
      icons.load(source_path <> "/Adwaita/symbolic")
    })

  let count = log.step("Code generation", fn() { generate.generate(icons) })
  io.println("Generated " <> int.to_string(count) <> " icons")
}
