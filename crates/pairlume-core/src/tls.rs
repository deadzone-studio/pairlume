// SPDX-License-Identifier: GPL-3.0-or-later
//! TLS 1.3 with a certificate on both ends. There is no authority to ask: a certificate is trusted because pairing
//! remembered its fingerprint. While pairing an unknown one is let in as far as the pairing talk, nothing else.
use crate::{
    ALPN,
    identity::{Fingerprint, Identity},
};
use anyhow::{Context, Result};
use rustls::{
    ClientConfig, DigitallySignedStruct, DistinguishedName, Error, ServerConfig, SignatureScheme,
    client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
    crypto::{CryptoProvider, ring::default_provider, verify_tls13_signature},
    pki_types::{CertificateDer, ServerName, UnixTime},
    server::danger::{ClientCertVerified, ClientCertVerifier},
};
use std::{fmt, sync::Arc};

/// may a device with this fingerprint connect at all?
pub type Gate = Arc<dyn Fn(&Fingerprint) -> bool + Send + Sync>;

struct Pinned {
    gate: Gate,
    provider: Arc<CryptoProvider>,
}

impl fmt::Debug for Pinned {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("Pinned")
    }
}

impl Pinned {
    fn check(&self, cert: &CertificateDer<'_>) -> Result<(), Error> {
        if (self.gate)(&Fingerprint::of(cert)) {
            Ok(())
        } else {
            Err(Error::InvalidCertificate(rustls::CertificateError::ApplicationVerificationFailure))
        }
    }
    // the other side has to prove that it has the key of the certificate it showed
    fn signed(&self, m: &[u8], c: &CertificateDer<'_>, d: &DigitallySignedStruct) -> Result<HandshakeSignatureValid, Error> {
        verify_tls13_signature(m, c, d, &self.provider.signature_verification_algorithms)
    }
    fn schemes(&self) -> Vec<SignatureScheme> {
        self.provider.signature_verification_algorithms.supported_schemes()
    }
}

fn no_tls12() -> Result<HandshakeSignatureValid, Error> {
    Err(Error::General("TLS 1.2 is not used".into()))
}

impl ServerCertVerifier for Pinned {
    fn verify_server_cert(
        &self,
        cert: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: &ServerName<'_>,
        _: &[u8],
        _: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        self.check(cert).map(|()| ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        _: &[u8],
        _: &CertificateDer<'_>,
        _: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        no_tls12()
    }
    fn verify_tls13_signature(
        &self,
        m: &[u8],
        c: &CertificateDer<'_>,
        d: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.signed(m, c, d)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.schemes()
    }
}

impl ClientCertVerifier for Pinned {
    fn root_hint_subjects(&self) -> &[DistinguishedName] {
        &[]
    }
    fn verify_client_cert(
        &self,
        cert: &CertificateDer<'_>,
        _: &[CertificateDer<'_>],
        _: UnixTime,
    ) -> Result<ClientCertVerified, Error> {
        self.check(cert).map(|()| ClientCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        _: &[u8],
        _: &CertificateDer<'_>,
        _: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        no_tls12()
    }
    fn verify_tls13_signature(
        &self,
        m: &[u8],
        c: &CertificateDer<'_>,
        d: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.signed(m, c, d)
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.schemes()
    }
}

pub fn server_config(id: &Identity, gate: Gate) -> Result<Arc<ServerConfig>> {
    let provider = Arc::new(default_provider());
    let v = Arc::new(Pinned { gate, provider: provider.clone() });
    let mut c = ServerConfig::builder_with_provider(provider)
        .with_protocol_versions(&[&rustls::version::TLS13])?
        .with_client_cert_verifier(v)
        .with_single_cert(vec![id.cert.clone()], id.key.clone_key())?;
    c.alpn_protocols = vec![ALPN.to_vec()];
    // every connection is checked against the list as it is now: no shortcut back in for an unpaired device
    c.session_storage = Arc::new(rustls::server::NoServerSessionStorage {});
    c.send_tls13_tickets = 0;
    Ok(Arc::new(c))
}

pub fn client_config(id: &Identity, gate: Gate) -> Result<Arc<ClientConfig>> {
    let provider = Arc::new(default_provider());
    let v = Arc::new(Pinned { gate, provider: provider.clone() });
    let mut c = ClientConfig::builder_with_provider(provider)
        .with_protocol_versions(&[&rustls::version::TLS13])?
        .dangerous()
        .with_custom_certificate_verifier(v)
        .with_client_auth_cert(vec![id.cert.clone()], id.key.clone_key())?;
    c.alpn_protocols = vec![ALPN.to_vec()];
    c.resumption = rustls::client::Resumption::disabled();
    Ok(Arc::new(c))
}

pub fn peer(certs: Option<&[CertificateDer<'_>]>) -> Result<Fingerprint> {
    Ok(Fingerprint::of(certs.and_then(|c| c.first()).context("the other side showed no certificate")?))
}
