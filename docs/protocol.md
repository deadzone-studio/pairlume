# Protocol 1

The computer listens on TCP (47321 by default); the phone connects.

## Finding the computer

mDNS service `_pairlume._tcp.local.` with TXT `v=1`, `id` (first 8 hex digits of the fingerprint), `name`,
`pairing` (`1` while the computer is pairing). These are hints only. Nothing in them is trusted.

## Link

TLS 1.3 only, ALPN `pairlume/1`, no session resumption. Both ends show a self-signed certificate (the programs here
make ECDSA P-256). The name and the dates in it mean nothing. The **fingerprint** is SHA-256 of the certificate (DER).
Both ends must check the handshake signature.

- Paired: each end accepts only the fingerprint it remembers.
- Pairing: the computer accepts an unknown one while its pairing window (120 s) is open, the phone while its user pairs.
  The other end is not trusted until pairing has succeeded.

Messages: 4 bytes length (big endian, 1 to 262144), then one JSON object with `t`. An unknown `t` is ignored. Hex is
lower case. First both ends send `hello` (`v`, `name`), the phone first. A different `v` ends the connection.

## Pairing

The phone sends `pair_start` with `mode`. `MAC(key, label, rest)` is HMAC-SHA256 over

    "pairlume 1 " label 0x00 computer_fingerprint phone_fingerprint rest

The fingerprints are those each end sees on the link, so someone in between makes them differ. One phone pairs at a
time. Whatever goes wrong closes the window; the next one has new digits and a new secret.

### `shake`

| | |
|---|---|
| phone | `commit` mac = MAC(Np, "shake", "") with Np 32 random bytes |
| computer | `nonce` Nc, 32 random bytes |
| phone | `nonce` Np; the computer checks the commitment |

Both show `SHA256("pairlume 1 code" 0x00 computer phone Nc Np)`, its first 8 bytes as a big endian number, mod 1000000,
six digits. Each end sends `confirm` with its user's answer; paired when both are `true`. The phone is bound to Np
before it sees Nc, so someone in between has one chance in a million.

### `qr`

The code is `pairlume://pair?v=1&a=ADDRESS:PORT&f=FINGERPRINT&s=SECRET` (16 random bytes). The phone connects only to
that fingerprint and sends `proof` MAC(secret, "qr phone", ""); the computer answers `proof` MAC(secret, "qr computer", "").

### `digits`

The digits (000000 to 999999) as a number, 20 rounds, lowest bit first, `rest` = round, bit (one byte each):

| | |
|---|---|
| computer | `commit` MAC(Nc, "digit computer", rest) |
| phone | `commit` MAC(Np, "digit phone", rest) |
| computer | `nonce` Nc; the phone checks and stops when it is wrong |
| phone | `nonce` Np; the computer checks and stops when it is wrong |

Fresh 32 random bytes every round. At the end the computer sends `confirm` true. This is Bluetooth's passkey entry: a
failed try can give away some of the digits, so they must never be used twice. The computer closes its window; **the
phone must not try the same digits again** either, also when it was the one to stop.

## A paired phone

The computer sends `allowed` (`caps`) at the start and when it changes. A message that needs a permission the phone
does not have is dropped and answered with `denied` (`cap`).

| from | message | needs |
|---|---|---|
| phone | `ping`; the computer answers `pong` | |
| phone | `battery` (`percent` 0 to 100, `charging`) | `battery` |

The phone sends something at least every 15 s; after 45 s of silence the computer closes the connection. A second
connection of the same phone replaces the first.

Permissions: `battery`, `sms`, `calls`, `notifications`, `files`, `clipboard`, `screen`, `camera`.
