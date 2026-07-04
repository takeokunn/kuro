use super::tests_support::*;
use crate::util::base64::{decode, encode, DecodeError};

#[test]
fn encode_cases_match_rfc_4648_vectors() {
    for case in [
        EncodeCase {
            name: "empty",
            input: b"",
            expected: "",
        },
        EncodeCase {
            name: "one byte",
            input: b"M",
            expected: "TQ==",
        },
        EncodeCase {
            name: "two bytes",
            input: b"Ma",
            expected: "TWE=",
        },
        EncodeCase {
            name: "three bytes",
            input: b"Man",
            expected: "TWFu",
        },
    ] {
        assert_eq!(encode(case.input), case.expected, "{}", case.name);
    }
}

#[test]
fn decode_cases_match_rfc_4648_vectors() {
    for case in [
        DecodeCase {
            name: "empty",
            input: b"",
            expected: b"",
        },
        DecodeCase {
            name: "one byte",
            input: b"TQ==",
            expected: b"M",
        },
        DecodeCase {
            name: "two bytes",
            input: b"TWE=",
            expected: b"Ma",
        },
        DecodeCase {
            name: "three bytes",
            input: b"TWFu",
            expected: b"Man",
        },
        DecodeCase {
            name: "embedded whitespace",
            input: b"TQ\n=\r=",
            expected: b"M",
        },
    ] {
        assert_eq!(decode(case.input).unwrap(), case.expected, "{}", case.name);
    }
}

#[test]
fn roundtrip_preserves_payload() {
    let data = b"Hello, world! This is a test of base64 encoding.";
    let encoded = encode(data);
    let decoded = decode(encoded.as_bytes()).unwrap();
    assert_eq!(decoded, data);
}

#[test]
fn malformed_decode_inputs_return_error() {
    for (name, input) in [
        ("invalid length", b"!!!".as_slice()),
        ("invalid first quartet byte", b"!!!!"),
        ("invalid second quartet byte", b"A!AA"),
        ("padding before third byte", b"A==="),
        ("padding followed by data", b"TQ=A"),
        ("data after padded quartet", b"TQ==AAAA"),
        ("too much padding", b"AAAA===="),
    ] {
        assert!(decode(input).is_err(), "{name}");
    }
}

#[test]
fn decode_error_display_names_base64_failure() {
    let msg = format!("{}", DecodeError);
    assert!(
        msg.contains("invalid") || msg.contains("base64"),
        "DecodeError display must mention invalid/base64 context, got: {msg:?}"
    );
}
