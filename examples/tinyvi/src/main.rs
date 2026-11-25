//! tinyvi — a small ratatui modal editor exercising luastd.

use std::io;

use crossterm::event::{Event, EventStream, KeyCode, KeyEventKind};
use futures::StreamExt;
use luastd_runtime::mlua::{self, Table};
use luastd_runtime::{Runtime, permissions};
use ratatui::Terminal;
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::style::{Color, Style};
use ratatui::text::{Line, Text};
use ratatui::widgets::Paragraph;
use tokio::time::{Duration, interval};

struct Editor {
    buffer: Vec<String>,
    status: String,
    mode: Mode,
    command: String,
}

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    Normal,
    Insert,
    Command,
}

impl Editor {
    fn new() -> Self {
        Self {
            buffer: vec![String::new()],
            status: "tinyvi — i insert, Esc normal, :q quit".into(),
            mode: Mode::Normal,
            command: String::new(),
        }
    }
}

fn main() -> io::Result<()> {
    crossterm::terminal::enable_raw_mode()?;
    let mut stdout = io::stdout();
    crossterm::execute!(stdout, crossterm::terminal::EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let rt = Runtime::builder()
        .permissions(permissions::allow_all())
        .effect::<luastd_runtime::Env>()
        .effect::<luastd_runtime::Fs>()
        .effect::<luastd_runtime::Process>()
        .build()
        .map_err(|e| io::Error::other(e.to_string()))?;

    let mut editor = Editor::new();

    rt.run(async |lua| {
        let mut events = EventStream::new();
        let mut tick = interval(Duration::from_millis(100));
        lua.load(
            r#"
            require("luastd.env")
            require("luastd.fs")
            require("luastd.process")
            local async = require("luastd.async")
            local fs = require("luastd.fs")
            local path = require("luastd.path")
            _G.__tinyvi_save = async.debounce(1000, function (p, contents)
                fs.write(path.new(p), contents)
            end)
            "#,
        )
        .exec_async()
        .await?;

        let tinyvi = lua.create_table()?;
        let commands: Table = lua.create_table()?;
        tinyvi.set("commands", commands)?;
        let log_fn = lua.create_function(|_, msg: String| { eprintln!("[tinyvi] {}", msg); Ok(()) })?;
        tinyvi.set("log", log_fn)?;
        let command_fn = lua.create_function(move |lua, (name, cb): (String, mlua::Function)| {
            let t: Table = lua.globals().get("tinyvi")?;
            let cmds: Table = t.get("commands")?;
            cmds.set(name, cb)?;
            Ok(())
        })?;
        tinyvi.set("command", command_fn)?;
        lua.globals().set("tinyvi", tinyvi)?;

        if let Some(p) = std::env::args().nth(1) {
            let src = std::fs::read_to_string(&p).unwrap_or_default();
            if !src.is_empty() {
                lua.load(src).set_name(&p).exec_async().await?;
            }
        }

        loop {
            terminal
                .draw(|f| {
                    let chunks = Layout::default()
                        .direction(Direction::Vertical)
                        .constraints([Constraint::Min(1), Constraint::Length(1)])
                        .split(f.area());
                    let text = Text::from(
                        editor
                            .buffer
                            .iter()
                            .enumerate()
                            .map(|(i, l)| Line::from(format!("{:>4}  {}", i + 1, l)))
                            .collect::<Vec<_>>(),
                    );
                    f.render_widget(Paragraph::new(text), chunks[0]);
                    let status = match editor.mode {
                        Mode::Normal => format!("-- NORMAL -- {}", editor.status),
                        Mode::Insert => format!("-- INSERT -- {}", editor.status),
                        Mode::Command => format!(":{}", editor.command),
                    };
                    f.render_widget(
                        Paragraph::new(status).style(Style::default().fg(Color::Yellow)),
                        chunks[1],
                    );
                })
                .map_err(mlua::Error::external)?;

            tokio::select! {
                maybe_event = events.next() => {
                    match maybe_event {
                        Some(Ok(Event::Key(key))) if key.kind == KeyEventKind::Press => {
                            match editor.mode {
                                Mode::Normal => match key.code {
                                    KeyCode::Char('i') => editor.mode = Mode::Insert,
                                    KeyCode::Char(':') => { editor.mode = Mode::Command; editor.command.clear(); }
                                    KeyCode::Char('q') => break,
                                    _ => {}
                                },
                                Mode::Insert => match key.code {
                                    KeyCode::Esc => editor.mode = Mode::Normal,
                                    KeyCode::Char(c) => {
                                        if editor.buffer.is_empty() { editor.buffer.push(String::new()); }
                                        editor.buffer[0].push(c);
                                        // autosave (debounced, 1s)
                                        let contents = editor.buffer[0].clone();
                                        let _ = lua.load(format!(
                                            r#"_G.__tinyvi_save("{}", [==[{}]==])"#,
                                            "/tmp/tinyvi_autosave.txt",
                                            contents.replace("]==]", "]===]")
                                        )).exec_async().await;
                                    }
                                    KeyCode::Backspace => {
                                        if !editor.buffer.is_empty() && !editor.buffer[0].is_empty() {
                                            editor.buffer[0].pop();
                                        }
                                    }
                                    KeyCode::Enter => editor.buffer.push(String::new()),
                                    _ => {}
                                },
                                Mode::Command => match key.code {
                                    KeyCode::Esc => { editor.mode = Mode::Normal; editor.command.clear(); }
                                    KeyCode::Enter => {
                                        let cmd = std::mem::take(&mut editor.command);
                                        editor.mode = Mode::Normal;
                                        if cmd == "q" {
                                            break;
                                        } else if let Some(pat) = cmd.strip_prefix("grep ") {
                                            let code = format!(
                                                r#"
                                                local process = require("luastd.process")
                                                local h = process.spawn("grep", {{ "-rn", {pat:?}, "." }})
                                                local res = {{}}
                                                for line in h:lines() do table.insert(res, line) end
                                                h:wait()
                                                _G.__tinyvi_grep = res
                                                "#,
                                            );
                                            let mut results = Vec::new();
                                            if lua.load(code.clone()).exec_async().await.is_ok()
                                                && let Ok(t) = lua.globals().get::<Table>("__tinyvi_grep") {
                                                    for s in t.sequence_values::<String>().flatten() { results.push(s); }
                                                }
                                            editor.status = format!("grep: {} results", results.len());
                                            // store for display
                                            let _ = results;
                                        } else {
                                            let cmds: Option<Table> = lua.globals().get::<Table>("tinyvi").ok().and_then(|t: Table| t.get::<Table>("commands").ok());
                                            if let Some(cmds) = cmds {
                                                if let Ok(cb) = cmds.get::<mlua::Function>(&*cmd) {
                                                    let _ = cb.call_async::<()>(()).await;
                                                    editor.status = format!("ran :{}", cmd);
                                                } else {
                                                    editor.status = format!("unknown command: {}", cmd);
                                                }
                                            }
                                        }
                                    }
                                    KeyCode::Char(c) => editor.command.push(c),
                                    KeyCode::Backspace => { editor.command.pop(); }
                                    _ => {}
                                },
                            }
                        }
                        Some(Ok(Event::Resize(_, _))) => {}
                        None => break,
                        _ => {}
                    }
                }
                _ = tick.tick() => {}
            }
        }

        crossterm::terminal::disable_raw_mode().map_err(mlua::Error::external)?;
        crossterm::execute!(terminal.backend_mut(), crossterm::terminal::LeaveAlternateScreen).map_err(mlua::Error::external)?;
        terminal.show_cursor().map_err(mlua::Error::external)?;
        Ok(())
    })
    .map_err(|e| io::Error::other(e.to_string()))?;

    Ok(())
}
