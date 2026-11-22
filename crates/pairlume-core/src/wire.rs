// SPDX-License-Identifier: GPL-3.0-or-later
//! Messages on a stream: the length (4 bytes, big endian), then JSON.
use crate::message::Msg;
use anyhow::{Context, Result, bail};
use std::time::Duration;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

/// a stranger must not be able to make us hold a lot of memory
pub const MAX_FRAME: usize = 256 * 1024;
pub const STEP: Duration = Duration::from_secs(15);

pub async fn send<W: AsyncWrite + Unpin>(w: &mut W, m: &Msg) -> Result<()> {
    let b = serde_json::to_vec(m)?;
    if b.len() > MAX_FRAME {
        bail!("message too large");
    }
    let mut out = Vec::with_capacity(b.len() + 4);
    out.extend_from_slice(&(b.len() as u32).to_be_bytes());
    out.extend_from_slice(&b);
    w.write_all(&out).await?;
    w.flush().await?;
    Ok(())
}

/// not cancel safe: a reader that waits for other things too keeps one `recv` going (see the daemon's session)
pub async fn recv<R: AsyncRead + Unpin>(r: &mut R) -> Result<Msg> {
    let mut len = [0; 4];
    r.read_exact(&mut len).await.context("the other side closed the connection")?;
    let len = u32::from_be_bytes(len) as usize;
    if len == 0 || len > MAX_FRAME {
        bail!("bad message length {len}");
    }
    let mut b = vec![0; len];
    r.read_exact(&mut b).await?;
    serde_json::from_slice(&b).context("not a message")
}

/// one step of a conversation: the answer has to come soon
pub async fn recv_step<R: AsyncRead + Unpin>(r: &mut R, limit: Duration) -> Result<Msg> {
    let m = tokio::time::timeout(limit, recv(r)).await.context("the other side did not answer in time")??;
    if let Msg::Fail { reason } = m {
        bail!("the other side stopped: {}", crate::store::clean_name(&reason));
    }
    Ok(m)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn round_trip_and_limits() {
        let (mut a, mut b) = tokio::io::duplex(1024);
        send(&mut a, &Msg::Battery { percent: 80, charging: true }).await.unwrap();
        assert_eq!(recv(&mut b).await.unwrap(), Msg::Battery { percent: 80, charging: true });
        a.write_all(&(MAX_FRAME as u32 + 1).to_be_bytes()).await.unwrap();
        assert!(recv(&mut b).await.is_err());
        let (mut a, mut b) = tokio::io::duplex(1024);
        a.write_all(&[0, 0, 0, 0]).await.unwrap();
        assert!(recv(&mut b).await.is_err());
    }

    #[tokio::test]
    async fn newer_messages_are_not_an_error() {
        let (mut a, mut b) = tokio::io::duplex(1024);
        let j = br#"{"t":"hologram","x":1}"#;
        a.write_all(&(j.len() as u32).to_be_bytes()).await.unwrap();
        a.write_all(j).await.unwrap();
        assert_eq!(recv(&mut b).await.unwrap(), Msg::Unknown);
    }
}
