//! floe — the Glacier OS package manager.
//!
//! floe drives pacman for the actual package work (dependency resolution, signature
//! checks, mirrors) and adds *generations*: after every change it records the full
//! installed package set, so `floe rollback` can return to any earlier state using the
//! package files pacman keeps in its cache.
mod gens;
mod pacman;
mod ui;

use gens::{Generation, Store};
use pacman::Pacman;
use std::io::{BufRead, Write};
use std::path::PathBuf;
use std::process::{Command, ExitCode};

type R<T> = Result<T, String>;

struct Opts {
    yes: bool,
    json: bool,
    rest: Vec<String>,
}

fn parse(args: &[String]) -> Opts {
    let mut o = Opts { yes: false, json: false, rest: vec![] };
    for a in args {
        match a.as_str() {
            "-y" | "--yes" | "--noconfirm" => o.yes = true,
            "--json" => o.json = true,
            _ => o.rest.push(a.clone()),
        }
    }
    o
}

fn main() -> ExitCode {
    // Behave like a normal Unix tool when the reader goes away (`floe search x | head`):
    // Rust ignores SIGPIPE by default, which turns that into a panic.
    #[cfg(unix)]
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_DFL);
    }
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(code) => code,
        Err(e) => {
            ui::err(&e);
            ExitCode::from(1)
        }
    }
}

fn exit(code: i32) -> ExitCode {
    ExitCode::from(code.clamp(0, 255) as u8)
}

fn run(args: &[String]) -> R<ExitCode> {
    let o = parse(args);
    let cmd = o.rest.first().map(String::as_str).unwrap_or("help");
    let operands: Vec<String> = o.rest.iter().skip(1).cloned().collect();
    let pm = Pacman::new();
    let store = Store::open();
    match cmd {
        "help" | "-h" | "--help" => {
            help();
            Ok(ExitCode::SUCCESS)
        }
        "version" | "-V" | "--version" => {
            println!("floe {}", env!("CARGO_PKG_VERSION"));
            Ok(ExitCode::SUCCESS)
        }
        "search" => search(&pm, &operands, o.json),
        "list" | "ls" => list(&pm, o.json),
        "info" => {
            let name = operands.first().ok_or("usage: floe info <package>")?;
            let local = pm.installed()?.contains_key(name);
            let flag = if local { "-Qi" } else { "-Si" };
            Ok(exit(pm.run(&[flag.to_string(), name.clone()])?))
        }
        "install" | "add" => {
            if operands.is_empty() {
                return Err("usage: floe install <package>...".into());
            }
            // -Syu, not -S: Arch does not support partial upgrades, and `floe refresh`
            // may have synced newer package lists than the installed system.
            let mut a = vec!["-Syu".to_string(), "--needed".to_string()];
            if o.yes {
                a.push("--noconfirm".into());
            }
            a.extend(operands.iter().cloned());
            mutate(&pm, &store, args, &format!("install {}", operands.join(" ")), &a)
        }
        "remove" | "rm" => {
            if operands.is_empty() {
                return Err("usage: floe remove <package>...".into());
            }
            let mut a = vec!["-Rs".to_string()];
            if o.yes {
                a.push("--noconfirm".into());
            }
            a.extend(operands.iter().cloned());
            mutate(&pm, &store, args, &format!("remove {}", operands.join(" ")), &a)
        }
        // Arch does not support partial upgrades, so "update" always means a full -Syu.
        "upgrade" | "update" => {
            let mut a = vec!["-Syu".to_string()];
            if o.yes {
                a.push("--noconfirm".into());
            }
            mutate(&pm, &store, args, "upgrade", &a)
        }
        // Download fresh package lists for `search`. Safe on its own because floe
        // never installs with plain -S (see install above).
        "refresh" => {
            ensure_root(args)?;
            let code = pm.run(&["-Sy".to_string()])?;
            if code == 0 {
                ui::ok("package lists are up to date");
            }
            Ok(exit(code))
        }
        "history" | "generations" => history(&store, o.json),
        "rollback" => rollback(&pm, &store, args, operands.first(), o.yes),
        other => Err(format!("unknown command '{other}' (see: floe help)")),
    }
}

fn help() {
    println!(
        "{} — Glacier OS package manager (pacman + generations)

usage: floe <command> [options]

  search <query>        search the repositories
  install <pkg>...      install packages (upgrades the system too, as Arch requires) (alias: add)
  remove <pkg>...       remove packages + unused deps (alias: rm)
  upgrade               full system upgrade         (alias: update)
  refresh               download fresh package lists (for search)
  list                  explicitly installed packages
  info <pkg>            package details
  history               list generations
  rollback [n]          return to generation n (default: the previous one)

options:
  -y, --yes             don't ask for confirmation
  --json                machine-readable output (search, list, history)

Every change creates a new generation. Rollback reinstalls exact versions from
pacman's package cache, so don't clean the cache of versions you may want back.",
        ui::accent("floe")
    );
}

/* ---------- read-only commands ---------- */

fn search(pm: &Pacman, q: &[String], json: bool) -> R<ExitCode> {
    let mut args = vec!["-Ss"];
    args.extend(q.iter().map(String::as_str));
    let out = pm.capture(&args).map_err(|e| {
        if e.contains("database file for") {
            "the package lists haven't been downloaded yet — run: floe refresh".to_string()
        } else {
            e
        }
    })?;
    let mut hits = pacman::parse_ss(&out);
    pacman::rank(&mut hits, &q.join(" "));
    if json {
        println!("{}", serde_json::to_string(&hits).map_err(|e| e.to_string())?);
        return Ok(ExitCode::SUCCESS);
    }
    if hits.is_empty() {
        ui::warn(&format!("no packages match '{}'", q.join(" ")));
        return Ok(ExitCode::from(1));
    }
    for h in &hits {
        let tag = if h.installed { ui::paint("1;32", " [installed]") } else { String::new() };
        println!("{}{} {}{}", ui::dim(&format!("{}/", h.repo)), ui::name(&h.name), ui::dim(&h.version), tag);
        println!("    {}", h.description);
    }
    Ok(ExitCode::SUCCESS)
}

fn list(pm: &Pacman, json: bool) -> R<ExitCode> {
    let all = pm.installed()?;
    let exp = pm.explicit()?;
    let rows: Vec<(&String, &String)> = all.iter().filter(|(n, _)| exp.contains(*n)).collect();
    if json {
        let v: Vec<_> = rows.iter().map(|(n, v)| serde_json::json!({"name": n, "version": v})).collect();
        println!("{}", serde_json::Value::Array(v));
        return Ok(ExitCode::SUCCESS);
    }
    ui::head(&format!("{} explicitly installed ({} total)", rows.len(), all.len()));
    let w = rows.iter().map(|(n, _)| n.len()).max().unwrap_or(0);
    for (n, v) in rows {
        println!("  {}  {}", ui::name(&format!("{n:w$}")), v);
    }
    Ok(ExitCode::SUCCESS)
}

fn history(store: &Store, json: bool) -> R<ExitCode> {
    let gens = store.list()?;
    if json {
        let v: Vec<_> = gens
            .iter()
            .map(|g| serde_json::json!({"n": g.n, "time": g.time, "action": g.action, "packages": g.packages.len()}))
            .collect();
        println!("{}", serde_json::Value::Array(v));
        return Ok(ExitCode::SUCCESS);
    }
    if gens.is_empty() {
        println!("no generations yet — the first change you make with floe creates one");
        return Ok(ExitCode::SUCCESS);
    }
    ui::head("generations");
    let now = gens::now();
    let last = gens.last().map(|g| g.n);
    for g in &gens {
        let cur = Some(g.n) == last;
        println!(
            "{} {:>4}  {:<12} {:>5} pkgs  {}{}",
            if cur { ui::accent("→") } else { " ".into() },
            g.n,
            ui::ago(g.time, now),
            g.packages.len(),
            g.action,
            if cur { ui::paint("1;32", "  (current)") } else { String::new() }
        );
    }
    Ok(ExitCode::SUCCESS)
}

/* ---------- privilege + bookkeeping ---------- */

#[cfg(unix)]
fn is_root() -> bool {
    unsafe { libc::geteuid() == 0 }
}
#[cfg(not(unix))]
fn is_root() -> bool {
    true
}

/// Mutating commands need root. Re-run ourselves through sudo instead of failing.
fn ensure_root(args: &[String]) -> R<()> {
    if is_root() || std::env::var_os("FLOE_NO_SUDO").is_some() {
        return Ok(());
    }
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let st = Command::new("sudo")
        .arg("--")
        .arg(exe)
        .args(args)
        .status()
        .map_err(|e| format!("this needs root and sudo could not be run: {e}"))?;
    std::process::exit(st.code().unwrap_or(1));
}

/// Make sure the newest generation matches the real system. Changes made with pacman
/// directly are recorded as their own generation so rollbacks stay accurate.
fn sync_external(pm: &Pacman, store: &Store) -> R<Generation> {
    let pkgs = pm.installed()?;
    let exp = pm.explicit()?;
    match store.latest()? {
        Some(g) if g.packages == pkgs && g.explicit == exp => Ok(g),
        Some(_) => store.record("external changes (outside floe)", pkgs, exp),
        None => store.record("initial state", pkgs, exp),
    }
}

/// Best-effort btrfs snapshot when snapper is configured (full-system safety net).
fn snapshot(desc: &str) {
    if std::env::var_os("FLOE_ROOT").is_some() || !std::path::Path::new("/etc/snapper/configs/root").exists() {
        return;
    }
    match Command::new("snapper").args(["-c", "root", "create", "-d", desc]).status() {
        Ok(s) if s.success() => {}
        _ => ui::warn("snapper snapshot failed; continuing without it"),
    }
}

fn record_if_changed(pm: &Pacman, store: &Store, before: &Generation, action: &str) -> R<Option<Generation>> {
    let pkgs = pm.installed()?;
    let exp = pm.explicit()?;
    if pkgs == before.packages && exp == before.explicit {
        return Ok(None);
    }
    Ok(Some(store.record(action, pkgs, exp)?))
}

fn mutate(pm: &Pacman, store: &Store, raw: &[String], action: &str, pacman_args: &[String]) -> R<ExitCode> {
    ensure_root(raw)?;
    let before = sync_external(pm, store)?;
    snapshot(&format!("floe: before {action}"));
    let code = pm.run(pacman_args)?;
    match record_if_changed(pm, store, &before, action)? {
        Some(g) => ui::ok(&format!("now on generation {} {}", g.n, ui::dim(&format!("(undo: floe rollback {})", before.n)))),
        None if code == 0 => println!("{}", ui::dim("nothing changed")),
        None => {}
    }
    Ok(exit(code))
}

fn confirm(q: &str) -> bool {
    print!("{} {q} [Y/n] ", ui::accent("::"));
    let _ = std::io::stdout().flush();
    let mut line = String::new();
    if std::io::stdin().lock().read_line(&mut line).is_err() {
        return false;
    }
    matches!(line.trim().to_lowercase().as_str(), "" | "y" | "yes")
}

fn rollback(pm: &Pacman, store: &Store, raw: &[String], target: Option<&String>, yes: bool) -> R<ExitCode> {
    ensure_root(raw)?;
    let cur = sync_external(pm, store)?;
    let gens = store.list()?;
    let target_n = match target {
        Some(s) => s.parse::<u64>().map_err(|_| format!("'{s}' is not a generation number"))?,
        None => match gens.len() {
            0 | 1 => return Err("nothing to roll back to yet (only one generation exists)".into()),
            n => gens[n - 2].n,
        },
    };
    let tgt = store.get(target_n)?;
    let p = gens::plan(&cur.packages, &cur.explicit, &tgt);
    if p.is_empty() {
        ui::ok(&format!("the system already matches generation {target_n}"));
        return Ok(ExitCode::SUCCESS);
    }

    let cache = std::env::var_os("FLOE_CACHE").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/var/cache/pacman/pkg"));
    let mut files = Vec::new();
    let mut missing = Vec::new();
    for (n, v) in &p.install {
        match gens::cache_file(&cache, n, v) {
            Some(f) => files.push(f.to_string_lossy().into_owned()),
            None => missing.push(format!("{n} {v}")),
        }
    }
    if !missing.is_empty() {
        return Err(format!(
            "cannot roll back to generation {target_n}: these package files are no longer in {}:\n  {}\nNothing was changed.",
            cache.display(),
            missing.join("\n  ")
        ));
    }

    ui::head(&format!("rolling back to generation {target_n} ({})", tgt.action));
    for (n, v) in &p.install {
        let verb = if cur.packages.contains_key(n) { "change" } else { "install" };
        let from = cur.packages.get(n).map(|o| format!("{o} → ")).unwrap_or_default();
        println!("  {} {} {}{}", ui::paint("32", verb), ui::name(n), ui::dim(&from), v);
    }
    for n in &p.remove {
        println!("  {} {}", ui::paint("31", "remove"), ui::name(n));
    }
    if !(p.as_deps.is_empty() && p.as_explicit.is_empty()) {
        println!("  {}", ui::dim(&format!("+ {} install-reason fixes", p.as_deps.len() + p.as_explicit.len())));
    }
    if !yes && !confirm("Proceed?") {
        println!("aborted — nothing was changed");
        return Ok(ExitCode::from(1));
    }

    snapshot(&format!("floe: before rollback to {target_n}"));
    let step = |args: Vec<String>, what: &str| -> R<()> {
        let code = pm.run(&args)?;
        if code != 0 {
            return Err(format!("pacman failed during {what} (exit {code})"));
        }
        Ok(())
    };
    let result = (|| -> R<()> {
        if !files.is_empty() {
            step([vec!["-U".into(), "--noconfirm".into()], files.clone()].concat(), "install")?;
        }
        if !p.remove.is_empty() {
            step([vec!["-R".into(), "--noconfirm".into()], p.remove.clone()].concat(), "removal")?;
        }
        if !p.as_deps.is_empty() {
            step([vec!["-D".into(), "--asdeps".into()], p.as_deps.clone()].concat(), "marking dependencies")?;
        }
        if !p.as_explicit.is_empty() {
            step([vec!["-D".into(), "--asexplicit".into()], p.as_explicit.clone()].concat(), "marking explicit packages")?;
        }
        Ok(())
    })();

    match (result, record_if_changed(pm, store, &cur, &format!("rollback to {target_n}"))?) {
        (Ok(()), Some(g)) => {
            ui::ok(&format!("now on generation {} — same packages as generation {target_n}", g.n));
            Ok(ExitCode::SUCCESS)
        }
        (Ok(()), None) => Ok(ExitCode::SUCCESS),
        (Err(e), Some(g)) => Err(format!("{e}; the partial result was recorded as generation {}. Run 'floe rollback {}' to return to where you started.", g.n, cur.n)),
        (Err(e), None) => Err(format!("{e}; nothing was changed")),
    }
}
