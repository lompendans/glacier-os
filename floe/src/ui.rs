//! Terminal output helpers. Colors are disabled when stdout is not a TTY or NO_COLOR is set.
use std::io::IsTerminal;

fn color() -> bool {
    std::env::var_os("NO_COLOR").is_none() && std::io::stdout().is_terminal()
}

pub fn paint(code: &str, s: &str) -> String {
    if color() {
        format!("\x1b[{code}m{s}\x1b[0m")
    } else {
        s.to_string()
    }
}

pub fn head(s: &str) {
    println!("{} {}", paint("1;36", "::"), paint("1", s));
}
pub fn ok(s: &str) {
    println!("{} {}", paint("1;32", "✓"), s);
}
pub fn warn(s: &str) {
    eprintln!("{} {}", paint("1;33", "warning:"), s);
}
pub fn err(s: &str) {
    eprintln!("{} {}", paint("1;31", "error:"), s);
}
pub fn dim(s: &str) -> String {
    paint("2", s)
}
pub fn accent(s: &str) -> String {
    paint("36", s)
}
pub fn name(s: &str) -> String {
    paint("1;35", s)
}

/// Human-friendly relative time ("just now", "5 min ago", "3 days ago").
pub fn ago(then: u64, now: u64) -> String {
    let d = now.saturating_sub(then);
    match d {
        0..=59 => "just now".into(),
        60..=3599 => format!("{} min ago", d / 60),
        3600..=86399 => format!("{} h ago", d / 3600),
        _ => {
            let days = d / 86400;
            format!("{days} day{} ago", if days == 1 { "" } else { "s" })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::ago;
    #[test]
    fn relative_times() {
        assert_eq!(ago(100, 100), "just now");
        assert_eq!(ago(0, 125), "2 min ago");
        assert_eq!(ago(0, 7200), "2 h ago");
        assert_eq!(ago(0, 86400), "1 day ago");
        assert_eq!(ago(0, 86400 * 3), "3 days ago");
        assert_eq!(ago(200, 100), "just now");
    }
}
