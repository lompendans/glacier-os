//! Thin wrapper around the pacman binary plus parsers for its output.
//! The binary can be overridden with FLOE_PACMAN (used by the end-to-end tests).
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};
use std::process::Command;

pub type Packages = BTreeMap<String, String>;

pub struct Pacman {
    bin: String,
}

impl Pacman {
    pub fn new() -> Self {
        Pacman { bin: std::env::var("FLOE_PACMAN").unwrap_or_else(|_| "pacman".into()) }
    }

    /// Run pacman and capture stdout. pacman exits 1 with empty stderr when a
    /// query simply has no results; that is treated as an empty, successful answer.
    pub fn capture(&self, args: &[&str]) -> Result<String, String> {
        let out = Command::new(&self.bin)
            .args(args)
            .env("LC_ALL", "C")
            .output()
            .map_err(|e| format!("failed to run {}: {e}", self.bin))?;
        let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
        if out.status.success() {
            return Ok(stdout);
        }
        let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
        if stderr.is_empty() {
            Ok(stdout)
        } else {
            Err(stderr)
        }
    }

    /// Run pacman interactively (inheriting the terminal) and return its exit code.
    pub fn run(&self, args: &[String]) -> Result<i32, String> {
        let st = Command::new(&self.bin)
            .args(args)
            .status()
            .map_err(|e| format!("failed to run {}: {e}", self.bin))?;
        Ok(st.code().unwrap_or(1))
    }

    pub fn installed(&self) -> Result<Packages, String> {
        Ok(parse_q(&self.capture(&["-Q"])?))
    }

    pub fn explicit(&self) -> Result<BTreeSet<String>, String> {
        Ok(parse_q(&self.capture(&["-Qe"])?).into_keys().collect())
    }
}

/// Parse `pacman -Q` output: one "name version" pair per line.
pub fn parse_q(s: &str) -> Packages {
    s.lines()
        .filter_map(|l| {
            let mut it = l.split_whitespace();
            Some((it.next()?.to_string(), it.next()?.to_string()))
        })
        .collect()
}

#[derive(Debug, PartialEq, Serialize)]
pub struct Hit {
    pub repo: String,
    pub name: String,
    pub version: String,
    pub description: String,
    pub installed: bool,
}

/// Parse `pacman -Ss` output:
/// ```text
/// extra/firefox 133.0-1 [installed]
///     Fast, Private & Safe Web Browser
/// ```
pub fn parse_ss(s: &str) -> Vec<Hit> {
    let mut hits: Vec<Hit> = Vec::new();
    for line in s.lines() {
        if line.starts_with(' ') || line.starts_with('\t') {
            if let Some(h) = hits.last_mut() {
                if !h.description.is_empty() {
                    h.description.push(' ');
                }
                h.description.push_str(line.trim());
            }
            continue;
        }
        let mut it = line.split_whitespace();
        let (Some(full), Some(version)) = (it.next(), it.next()) else { continue };
        let (repo, name) = full.split_once('/').unwrap_or(("", full));
        hits.push(Hit {
            repo: repo.into(),
            name: name.into(),
            version: version.into(),
            description: String::new(),
            installed: line.contains("[installed"),
        });
    }
    hits
}

/// Order search hits by relevance to `query` (pacman lists them alphabetically):
/// exact name, then name prefix, then name contains, then description-only matches.
/// The sort is stable, so ties keep pacman's order.
pub fn rank(hits: &mut [Hit], query: &str) {
    let q = query.trim().to_lowercase();
    if q.is_empty() {
        return;
    }
    hits.sort_by_key(|h| {
        let n = h.name.to_lowercase();
        if n == q {
            0
        } else if n.starts_with(&q) {
            1
        } else if n.contains(&q) {
            2
        } else {
            3
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hit(name: &str) -> Hit {
        Hit { repo: "extra".into(), name: name.into(), version: "1-1".into(), description: String::new(), installed: false }
    }

    #[test]
    fn ranks_by_relevance() {
        let mut h = vec![hit("aws-sdk-cpp-firehose"), hit("browserpass-firefox"), hit("cutter"), hit("firefox"), hit("firefox-i18n-de"), hit("Fire")];
        rank(&mut h, "fire");
        let names: Vec<&str> = h.iter().map(|x| x.name.as_str()).collect();
        assert_eq!(names, ["Fire", "firefox", "firefox-i18n-de", "aws-sdk-cpp-firehose", "browserpass-firefox", "cutter"]);
        let mut same = vec![hit("b"), hit("a")];
        rank(&mut same, "");
        assert_eq!(same[0].name, "b");
    }

    #[test]
    fn parses_query() {
        let p = parse_q("bash 5.2.037-1\nfirefox 133.0-1\n\nbroken\nlib32-foo 1:2.0-3\n");
        assert_eq!(p.len(), 3);
        assert_eq!(p["firefox"], "133.0-1");
        assert_eq!(p["lib32-foo"], "1:2.0-3");
    }

    #[test]
    fn parses_search() {
        let out = "extra/firefox 133.0-1 [installed]\n    Fast, Private & Safe Web Browser\n\
                   core/git 2.47.0-1 (base-devel) [installed: 2.46.0-1]\n    the fast distributed\n    version control system\n\
                   extra/krita 5.2.6-1\n    Edit and paint images\n";
        let h = parse_ss(out);
        assert_eq!(h.len(), 3);
        assert_eq!(h[0], Hit { repo: "extra".into(), name: "firefox".into(), version: "133.0-1".into(), description: "Fast, Private & Safe Web Browser".into(), installed: true });
        assert!(h[1].installed);
        assert_eq!(h[1].description, "the fast distributed version control system");
        assert!(!h[2].installed);
    }

    #[test]
    fn empty_search() {
        assert!(parse_ss("").is_empty());
    }
}
