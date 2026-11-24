// SPDX-License-Identifier: GPL-3.0-or-later
//! Paired devices and what each of them may do.
use crate::{identity::Fingerprint, message::Capability};
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    io::Write,
    os::unix::fs::{DirBuilderExt, OpenOptionsExt},
    path::{Path, PathBuf},
};

/// only for this user, and never half written
pub fn write_private(path: &Path, data: &[u8]) -> Result<()> {
    let dir = path.parent().context("no folder")?;
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    let tmp = path.with_extension("tmp");
    let _ = std::fs::remove_file(&tmp);
    let mut f = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&tmp)?;
    f.write_all(data)?;
    f.sync_all()?;
    std::fs::rename(&tmp, path)?;
    Ok(())
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Device {
    pub name: String,
    /// nothing is allowed until the user allows it
    #[serde(default)]
    pub allowed: BTreeSet<Capability>,
}

#[derive(Debug)]
pub struct Store {
    path: PathBuf,
    devices: BTreeMap<Fingerprint, Device>,
}

impl Store {
    pub fn open(dir: &Path) -> Result<Self> {
        let path = dir.join("devices.json");
        let devices = match std::fs::read(&path) {
            Ok(b) => serde_json::from_slice(&b).with_context(|| format!("{} is damaged", path.display()))?,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => BTreeMap::new(),
            Err(e) => return Err(e.into()),
        };
        Ok(Self { path, devices })
    }
    pub fn get(&self, fp: &Fingerprint) -> Option<&Device> {
        self.devices.get(fp)
    }
    pub fn iter(&self) -> impl Iterator<Item = (&Fingerprint, &Device)> {
        self.devices.iter()
    }
    pub fn add(&mut self, fp: Fingerprint, name: &str) -> Result<()> {
        self.devices.insert(fp, Device { name: clean_name(name), allowed: BTreeSet::new() });
        self.save()
    }
    pub fn remove(&mut self, fp: &Fingerprint) -> Result<bool> {
        let had = self.devices.remove(fp).is_some();
        self.save()?;
        Ok(had)
    }
    pub fn set_allowed(&mut self, fp: &Fingerprint, cap: Capability, on: bool) -> Result<()> {
        let d = self.devices.get_mut(fp).context("this device is not paired")?;
        if on {
            d.allowed.insert(cap)
        } else {
            d.allowed.remove(&cap)
        };
        self.save()
    }
    /// a device by its fingerprint, the start of it, or its name; only when exactly one fits
    pub fn find(&self, who: &str) -> Result<Fingerprint> {
        let hits: Vec<_> = (self.devices.iter())
            .filter(|(fp, d)| d.name == who || (who.len() >= 4 && fp.to_string().starts_with(who)))
            .map(|(fp, _)| *fp)
            .collect();
        match hits[..] {
            [fp] => Ok(fp),
            [] => anyhow::bail!("no paired device is called \"{who}\""),
            _ => anyhow::bail!("more than one device fits \"{who}\": use its id"),
        }
    }
    fn save(&self) -> Result<()> {
        write_private(&self.path, &serde_json::to_vec_pretty(&self.devices)?)
    }
}

/// a name from the other side: one short line, nothing that could play with a terminal or a window
pub fn clean_name(s: &str) -> String {
    let n = clean_line(s, 48);
    if n.is_empty() { "Unnamed device".into() } else { n }
}

/// one line from the other side, at most `max` characters; empty stays empty (a number the network hides, a title)
pub fn clean_line(s: &str, max: usize) -> String {
    let hidden = |c: char| {
        c.is_control() || matches!(c, '\u{200b}'..='\u{200f}' | '\u{202a}'..='\u{202e}' | '\u{2060}'..='\u{206f}' | '\u{feff}')
    };
    let n: String = s.chars().filter(|c| !hidden(*c)).take(max).collect();
    n.trim().into()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn devices_start_with_nothing_allowed() {
        let d = tempfile::tempdir().unwrap();
        let fp = Fingerprint([7; 32]);
        let mut s = Store::open(d.path()).unwrap();
        s.add(fp, "Phone").unwrap();
        assert!(s.get(&fp).unwrap().allowed.is_empty());
        s.set_allowed(&fp, Capability::Battery, true).unwrap();
        let s = Store::open(d.path()).unwrap();
        assert!(s.get(&fp).unwrap().allowed.contains(&Capability::Battery));
        assert_eq!(s.find("Phone").unwrap(), fp);
        assert_eq!(s.find("0707").unwrap(), fp);
        assert!(s.find("07").is_err());
    }

    #[test]
    fn names_are_one_plain_line() {
        assert_eq!(clean_name("My\x1b[31m\nphone\u{202e}"), "My[31mphone");
        assert_eq!(clean_name(" \t "), "Unnamed device");
        assert_eq!(clean_name(&"x".repeat(500)).len(), 48);
    }

    #[test]
    fn a_damaged_list_is_not_thrown_away() {
        let d = tempfile::tempdir().unwrap();
        std::fs::write(d.path().join("devices.json"), b"{oops").unwrap();
        assert!(Store::open(d.path()).is_err());
    }
}
