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
      version: "40.1",
      url: "https://gitlab.gnome.org/GNOME/adwaita-icon-theme/-/archive/40.1/adwaita-icon-theme-40.1.tar.gz",
      root: "adwaita-icon-theme-40.1",
      sha256: "6a13f97bf12eb24b00a72335c37324ac51556050115d7b3fdcdb83f081039d28",
    )

  let icons =
    log.step("Icons loading", fn() {
      icons.load(source_path <> "/Adwaita/scalable")
    })

  let count = log.step("Code generation", fn() { generate.generate(icons) })
  io.println("Generated " <> int.to_string(count) <> " icons")
}
