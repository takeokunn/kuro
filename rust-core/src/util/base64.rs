//! Self-contained RFC 4648 base64 encode/decode (standard alphabet, with padding).

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const INVALID: u8 = 0xFF;
const PAD: u8 = b'=';
const DECODE_TABLE: [u8; 256] = build_decode_table();

const fn build_decode_table() -> [u8; 256] {
    let mut table = [INVALID; 256];
    let mut i = 0;
    while i < ALPHABET.len() {
        table[ALPHABET[i] as usize] = i as u8;
        i += 1;
    }
    table
}

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
    let filtered = without_decode_whitespace(input);
    if filtered.is_empty() {
        return Ok(Vec::new());
    }
    if !filtered.len().is_multiple_of(4) || has_invalid_padding(&filtered) {
        return Err(DecodeError);
    }

    let mut out = Vec::with_capacity(filtered.len() / 4 * 3);
    for chunk in filtered.chunks(4) {
        decode_quartet(chunk, &mut out)?;
    }
    Ok(out)
}

fn without_decode_whitespace(input: &[u8]) -> Vec<u8> {
    input
        .iter()
        .copied()
        .filter(|&b| !is_decode_whitespace(b))
        .collect()
}

fn is_decode_whitespace(byte: u8) -> bool {
    matches!(byte, b'\n' | b'\r' | b' ')
}

fn has_invalid_padding(input: &[u8]) -> bool {
    let Some(first_pad) = input.iter().position(|&b| b == PAD) else {
        return false;
    };
    let pad_count = input.len() - first_pad;
    let pad_offset = first_pad % 4;

    pad_offset < 2 || pad_count > 2 || input[first_pad..].iter().any(|&b| b != PAD)
}

fn decode_quartet(chunk: &[u8], out: &mut Vec<u8>) -> Result<(), DecodeError> {
    debug_assert_eq!(chunk.len(), 4);

    let c0 = decode_required(chunk[0])?;
    let c1 = decode_required(chunk[1])?;
    let c2 = decode_optional(chunk[2])?;
    let c3 = decode_optional(chunk[3])?;

    out.push((c0 << 2) | (c1 >> 4));
    if let Some(c2) = c2 {
        out.push((c1 << 4) | (c2 >> 2));
        if let Some(c3) = c3 {
            out.push((c2 << 6) | c3);
        }
    }

    Ok(())
}

fn decode_required(byte: u8) -> Result<u8, DecodeError> {
    let value = DECODE_TABLE[byte as usize];
    if value == INVALID {
        Err(DecodeError)
    } else {
        Ok(value)
    }
}

fn decode_optional(byte: u8) -> Result<Option<u8>, DecodeError> {
    if byte == PAD {
        Ok(None)
    } else {
        decode_required(byte).map(Some)
    }
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
mod tests;
