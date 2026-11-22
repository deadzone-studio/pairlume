// SPDX-License-Identifier: GPL-3.0-or-later
//! A device is its self-signed certificate. Its fingerprint is what pairing remembers.
use anyhow::{Context, Result, bail};
use ring::digest;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use std::{fmt, path::Path, str::FromStr};

#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Fingerprint(pub [u8; 32]);

impl Fingerprint {
    pub fn of(cert: &CertificateDer<'_>) -> Self {
        let d = digest::digest(&digest::SHA256, cert.as_ref());
        Self(d.as_ref().try_into().expect("SHA-256 is 32 bytes"))
    }
    /// the first bytes, for names in lists (never to decide anything)
    pub fn short(&self) -> String {
        to_hex(&self.0[..4])
    }
}

impl fmt::Display for Fingerprint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&to_hex(&self.0))
    }
}
impl fmt::Debug for Fingerprint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Fingerprint({})", self.short())
    }
}
impl FromStr for Fingerprint {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self> {
        Ok(Self(from_hex(s)?.try_into().ok().context("a fingerprint is 32 bytes")?))
    }
}
impl serde::Serialize for Fingerprint {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(self)
    }
}
impl<'de> serde::Deserialize<'de> for Fingerprint {
    fn deserialize<D: serde::Deserializer<'de>>(d: D) -> Result<Self, D::Error> {
        String::deserialize(d)?.parse().map_err(serde::de::Error::custom)
    }
}

pub fn to_hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

pub fn from_hex(s: &str) -> Result<Vec<u8>> {
    let b = s.as_bytes();
    if !b.len().is_multiple_of(2) {
        bail!("odd number of hex digits");
    }
    let nib = |c: u8| (c as char).to_digit(16).context("not a hex digit");
    b.chunks(2).map(|p| Ok((nib(p[0])? * 16 + nib(p[1])?) as u8)).collect()
}

pub struct Identity {
    pub cert: CertificateDer<'static>,
    pub key: PrivateKeyDer<'static>,
    pub fingerprint: Fingerprint,
}

impl Clone for Identity {
    fn clone(&self) -> Self {
        Self { cert: self.cert.clone(), key: self.key.clone_key(), fingerprint: self.fingerprint }
    }
}

impl Identity {
    fn new(cert: CertificateDer<'static>, key: Vec<u8>) -> Self {
        let fingerprint = Fingerprint::of(&cert);
        Self { cert, key: PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key)), fingerprint }
    }

    pub fn generate() -> Result<Self> {
        let ck = rcgen::generate_simple_self_signed(vec!["pairlume".into()])?;
        Ok(Self::new(ck.cert.der().clone(), ck.signing_key.serialize_der()))
    }

    /// the identity in `dir`, made on the first start
    pub fn load_or_create(dir: &Path) -> Result<Self> {
        let (cert, key) = (dir.join("identity.crt"), dir.join("identity.key"));
        match (std::fs::read(&cert), std::fs::read(&key)) {
            (Ok(c), Ok(k)) => Ok(Self::new(CertificateDer::from(c), k)),
            (Err(a), Err(b)) if a.kind() == std::io::ErrorKind::NotFound && b.kind() == std::io::ErrorKind::NotFound => {
                let id = Self::generate()?;
                crate::store::write_private(&key, id.key.secret_der())?;
                crate::store::write_private(&cert, id.cert.as_ref())?;
                Ok(id)
            }
            // half an identity: making a new one would silently unpair every device
            _ => bail!("the identity in {} is incomplete or cannot be read", dir.display()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hex_round_trip() {
        assert_eq!(from_hex(&to_hex(&[0, 1, 254, 255])).unwrap(), [0, 1, 254, 255]);
        assert!(from_hex("abc").is_err());
        assert!(from_hex("zz").is_err());
        assert!(from_hex("+1").is_err());
        assert!(from_hex("łł").is_err());
    }

    #[test]
    fn identity_survives_a_restart_and_is_private() {
        use std::os::unix::fs::PermissionsExt;
        let d = tempfile::tempdir().unwrap();
        let a = Identity::load_or_create(d.path()).unwrap();
        let b = Identity::load_or_create(d.path()).unwrap();
        assert_eq!(a.fingerprint, b.fingerprint);
        let mode = std::fs::metadata(d.path().join("identity.key")).unwrap().permissions().mode();
        assert_eq!(mode & 0o777, 0o600);
        std::fs::remove_file(d.path().join("identity.crt")).unwrap();
        assert!(Identity::load_or_create(d.path()).is_err());
    }
}
