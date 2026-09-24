import gleam/io
import pocket_watch

const prefix = "[adwaita_lustre_dev] "

pub fn step(label: String, run body: fn() -> value) -> value {
  io.println(prefix <> label <> ": starting")
  pocket_watch.callback(
    fn(elapsed) { io.println(prefix <> label <> ": completed in " <> elapsed) },
    body,
  )
}

pub fn skipped(label: String, reason: String) -> Nil {
  io.println(prefix <> label <> ": skipped (" <> reason <> ")")
}
