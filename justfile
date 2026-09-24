build:
    rm -f src/adwaita_lustre.gleam
    gleam run -m adwaita_lustre_dev
    gleam format
