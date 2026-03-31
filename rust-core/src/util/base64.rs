//! Self-contained RFC 4648 base64 encode/decode (standard alphabet, with padding).

const ALPHABET: &[u8; 64] =
    b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/// Encode `input` to base64 (standard alphabet, `=` padding).
pub(crate) fn encode(input: &[u8]) -> String {
    if input.is_empty() {
        return String::new();
    }
    let out_len = input.len().div_ceil(3) * 4;
    let mut out = Vec::with_capacity(out_len);
    for chunk in input.chunks(3) {
        let b0 = chunk[0];
        let b1 = if chunk.len() > 1 { chunk[1] } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] } else { 0 };
        out.push(ALPHABET[((b0 >> 2) & 0x3F) as usize]);
        out.push(ALPHABET[(((b0 & 0x3) << 4) | (b1 >> 4)) as usize]);
        out.push(if chunk.len() > 1 {
            ALPHABET[(((b1 & 0xF) << 2) | (b2 >> 6)) as usize]
        } else {
            b'='
        });
        out.push(if chunk.len() > 2 {
            ALPHABET[(b2 & 0x3F) as usize]
        } else {
            b'='
        });
    }
    // SAFETY: ALPHABET contains only ASCII bytes; b'=' is ASCII.
    unsafe { String::from_utf8_unchecked(out) }
}

/// Decode base64 (standard alphabet, `=` padding). Returns `Err` on invalid input.
///
/// Whitespace (`\n`, `\r`, ` `) is stripped before decoding.
pub(crate) fn decode(input: &[u8]) -> Result<Vec<u8>, DecodeError> {
    // Build reverse-lookup table: 0xFF = invalid character.
    let mut table = [0xFFu8; 256];
    for (i, &c) in ALPHABET.iter().enumerate() {
        table[c as usize] = i as u8;
    }

    // Strip whitespace.
    let filtered: Vec<u8> = input
        .iter()
        .copied()
        .filter(|&b| b != b'\n' && b != b'\r' && b != b' ')
        .collect();

    if filtered.is_empty() {
        return Ok(Vec::new());
    }

    if !filtered.len().is_multiple_of(4) {
        return Err(DecodeError);
    }

    let mut out = Vec::with_capacity(filtered.len() / 4 * 3);
    for chunk in filtered.chunks(4) {
        let c0 = table[chunk[0] as usize];
        let c1 = table[chunk[1] as usize];

        if c0 == 0xFF || c1 == 0xFF {
            return Err(DecodeError);
        }

        let c2 = if chunk[2] == b'=' {
            0u8
        } else {
            let v = table[chunk[2] as usize];
            if v == 0xFF {
                return Err(DecodeError);
            }
            v
        };
        let c3 = if chunk[3] == b'=' {
            0u8
        } else {
            let v = table[chunk[3] as usize];
            if v == 0xFF {
                return Err(DecodeError);
            }
            v
        };

        out.push((c0 << 2) | (c1 >> 4));
        if chunk[2] != b'=' {
            out.push((c1 << 4) | (c2 >> 2));
        }
        if chunk[3] != b'=' {
            out.push((c2 << 6) | c3);
        }
    }
    Ok(out)
}

/// Error returned when base64 input is malformed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct DecodeError;

impl std::fmt::Display for DecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "invalid base64 encoding")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode_empty() {
        assert_eq!(encode(b""), "");
    }

    #[test]
    fn test_encode_one_byte() {
        // b"M" = 0x4D = 0100_1101; encodes to "TQ=="
        assert_eq!(encode(b"M"), "TQ==");
    }

    #[test]
    fn test_encode_two_bytes() {
        // b"Ma" encodes to "TWE="
        assert_eq!(encode(b"Ma"), "TWE=");
    }

    #[test]
    fn test_encode_three_bytes() {
        // b"Man" encodes to "TWFu" (no padding)
        assert_eq!(encode(b"Man"), "TWFu");
    }

    #[test]
    fn test_roundtrip() {
        let data = b"Hello, world! This is a test of base64 encoding.";
        let encoded = encode(data);
        let decoded = decode(encoded.as_bytes()).unwrap();
        assert_eq!(decoded, data);
    }

    #[test]
    fn test_decode_with_padding() {
        assert_eq!(decode(b"TQ==").unwrap(), b"M");
        assert_eq!(decode(b"TWE=").unwrap(), b"Ma");
        assert_eq!(decode(b"TWFu").unwrap(), b"Man");
    }

    #[test]
    fn test_decode_invalid() {
        assert!(decode(b"!!!").is_err());
    }
}
