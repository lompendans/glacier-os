//! Generations: numbered, immutable snapshots of the installed package set.
//! Stored as JSON under $FLOE_ROOT/var/lib/floe/generations/<n>.json (FLOE_ROOT defaults to /).
//! The newest generation is always the current one; rollbacks append a new generation.
use crate::pacman::Packages;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct Generation {
    pub n: u64,
    pub time: u64,
    pub action: String,
    pub packages: Packages,
    pub explicit: BTreeSet<String>,
}

pub struct Store {
    dir: PathBuf,
}

pub fn now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn write_atomic(path: &Path, data: &[u8]) -> Result<(), String> {
    let parent = path.parent().ok_or("invalid path")?;
    fs::create_dir_all(parent).map_err(|e| format!("cannot create {}: {e}", parent.display()))?;
    let tmp = path.with_extension("tmp");
    let mut f = fs::File::create(&tmp).map_err(|e| format!("cannot write {}: {e}", tmp.display()))?;
    f.write_all(data).and_then(|_| f.sync_all()).map_err(|e| format!("cannot write {}: {e}", tmp.display()))?;
    fs::rename(&tmp, path).map_err(|e| format!("cannot write {}: {e}", path.display()))
}

impl Store {
    pub fn open() -> Self {
        let root = std::env::var_os("FLOE_ROOT").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("/"));
        Store::at(root.join("var/lib/floe"))
    }

    pub fn at(dir: PathBuf) -> Self {
        Store { dir }
    }

    fn gen_dir(&self) -> PathBuf {
        self.dir.join("generations")
    }

    pub fn list(&self) -> Result<Vec<Generation>, String> {
        let dir = self.gen_dir();
        let rd = match fs::read_dir(&dir) {
            Ok(rd) => rd,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(vec![]),
            Err(e) => return Err(format!("cannot read {}: {e}", dir.display())),
        };
        let mut out = Vec::new();
        for entry in rd {
            let path = entry.map_err(|e| e.to_string())?.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            let text = fs::read_to_string(&path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
            let g: Generation = serde_json::from_str(&text).map_err(|e| format!("corrupt generation {}: {e}", path.display()))?;
            out.push(g);
        }
        out.sort_by_key(|g| g.n);
        Ok(out)
    }

    pub fn latest(&self) -> Result<Option<Generation>, String> {
        Ok(self.list()?.pop())
    }

    pub fn get(&self, n: u64) -> Result<Generation, String> {
        self.list()?.into_iter().find(|g| g.n == n).ok_or_else(|| format!("generation {n} does not exist (see: floe history)"))
    }

    pub fn record(&self, action: &str, packages: Packages, explicit: BTreeSet<String>) -> Result<Generation, String> {
        let n = self.latest()?.map(|g| g.n + 1).unwrap_or(1);
        let g = Generation { n, time: now(), action: action.to_string(), packages, explicit };
        let json = serde_json::to_vec_pretty(&g).map_err(|e| e.to_string())?;
        write_atomic(&self.gen_dir().join(format!("{n}.json")), &json)?;
        Ok(g)
    }
}

/// What has to happen to turn the current system into `target`.
#[derive(Debug, Default, PartialEq)]
pub struct Plan {
    /// (name, version) to install or up/downgrade from the package cache.
    pub install: Vec<(String, String)>,
    pub remove: Vec<String>,
    pub as_explicit: Vec<String>,
    pub as_deps: Vec<String>,
}

impl Plan {
    pub fn is_empty(&self) -> bool {
        self.install.is_empty() && self.remove.is_empty() && self.as_explicit.is_empty() && self.as_deps.is_empty()
    }
}

/// Compute a rollback plan. Mirrors pacman semantics: `pacman -U` marks *newly installed*
/// packages as explicit and keeps the install reason of packages that were already present.
pub fn plan(cur: &Packages, cur_explicit: &BTreeSet<String>, target: &Generation) -> Plan {
    let install: Vec<(String, String)> = target
        .packages
        .iter()
        .filter(|(n, v)| cur.get(*n) != Some(*v))
        .map(|(n, v)| (n.clone(), v.clone()))
        .collect();
    let remove = cur.keys().filter(|n| !target.packages.contains_key(*n)).cloned().collect();
    let as_explicit = target
        .explicit
        .iter()
        .filter(|n| target.packages.contains_key(*n) && !cur_explicit.contains(*n) && cur.contains_key(*n))
        .cloned()
        .collect();
    let as_deps = target
        .packages
        .keys()
        .filter(|n| !target.explicit.contains(*n))
        .filter(|n| cur_explicit.contains(*n) || !cur.contains_key(*n))
        .cloned()
        .collect();
    Plan { install, remove, as_explicit, as_deps }
}

/// Locate a package file in pacman's cache (e.g. firefox-133.0-1-x86_64.pkg.tar.zst).
pub fn cache_file(cache: &Path, name: &str, version: &str) -> Option<PathBuf> {
    for arch in ["x86_64", "any"] {
        for ext in ["zst", "xz", "gz"] {
            let p = cache.join(format!("{name}-{version}-{arch}.pkg.tar.{ext}"));
            if p.is_file() {
                return Some(p);
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pk(v: &[(&str, &str)]) -> Packages {
        v.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect()
    }
    fn set(v: &[&str]) -> BTreeSet<String> {
        v.iter().map(|s| s.to_string()).collect()
    }
    fn gen(packages: Packages, explicit: BTreeSet<String>) -> Generation {
        Generation { n: 1, time: 0, action: "t".into(), packages, explicit }
    }

    #[test]
    fn identical_state_is_empty_plan() {
        let p = pk(&[("bash", "5.2-1"), ("nss", "3.1-1")]);
        let e = set(&["bash"]);
        assert!(plan(&p, &e, &gen(p.clone(), e.clone())).is_empty());
    }

    #[test]
    fn reinstall_removed_package_with_its_dependency() {
        let cur = pk(&[("bash", "5.2-1")]);
        let target = gen(pk(&[("bash", "5.2-1"), ("firefox", "133-1"), ("nss", "3.1-1")]), set(&["bash", "firefox"]));
        let p = plan(&cur, &set(&["bash"]), &target);
        assert_eq!(p.install, vec![("firefox".into(), "133-1".into()), ("nss".into(), "3.1-1".into())]);
        assert!(p.remove.is_empty());
        // new installs via -U become explicit, so the dependency must be re-marked
        assert_eq!(p.as_deps, vec!["nss".to_string()]);
        assert!(p.as_explicit.is_empty());
    }

    #[test]
    fn downgrade_and_remove() {
        let cur = pk(&[("bash", "5.2-1"), ("krita", "5.3-1"), ("vlc", "3.0-1")]);
        let target = gen(pk(&[("bash", "5.2-1"), ("krita", "5.2-1")]), set(&["bash", "krita"]));
        let p = plan(&cur, &set(&["bash", "krita", "vlc"]), &target);
        assert_eq!(p.install, vec![("krita".into(), "5.2-1".into())]);
        assert_eq!(p.remove, vec!["vlc".to_string()]);
        assert!(p.as_deps.is_empty() && p.as_explicit.is_empty());
    }

    #[test]
    fn install_reason_changes_only() {
        let cur = pk(&[("a", "1-1"), ("b", "1-1")]);
        let target = gen(cur.clone(), set(&["b"]));
        let p = plan(&cur, &set(&["a"]), &target);
        assert!(p.install.is_empty() && p.remove.is_empty());
        assert_eq!(p.as_explicit, vec!["b".to_string()]);
        assert_eq!(p.as_deps, vec!["a".to_string()]);
    }

    #[test]
    fn store_roundtrip_and_numbering() {
        let dir = std::env::temp_dir().join(format!("floe-test-{}-{}", std::process::id(), now()));
        let s = Store::at(dir.clone());
        assert!(s.latest().unwrap().is_none());
        let g1 = s.record("initial", pk(&[("bash", "5.2-1")]), set(&["bash"])).unwrap();
        let g2 = s.record("install x", pk(&[("bash", "5.2-1"), ("x", "1-1")]), set(&["bash", "x"])).unwrap();
        assert_eq!((g1.n, g2.n), (1, 2));
        assert_eq!(s.list().unwrap().len(), 2);
        assert_eq!(s.get(1).unwrap(), g1);
        assert_eq!(s.latest().unwrap().unwrap(), g2);
        assert!(s.get(9).is_err());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn finds_cached_files() {
        let dir = std::env::temp_dir().join(format!("floe-cache-{}-{}", std::process::id(), now()));
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("firefox-133.0-1-x86_64.pkg.tar.zst"), b"").unwrap();
        fs::write(dir.join("fonts-1.0-1-any.pkg.tar.zst"), b"").unwrap();
        assert!(cache_file(&dir, "firefox", "133.0-1").is_some());
        assert!(cache_file(&dir, "fonts", "1.0-1").is_some());
        assert!(cache_file(&dir, "firefox", "132.0-1").is_none());
        fs::remove_dir_all(dir).unwrap();
    }
}
