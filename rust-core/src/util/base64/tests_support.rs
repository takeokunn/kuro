pub(crate) struct EncodeCase {
    pub(crate) name: &'static str,
    pub(crate) input: &'static [u8],
    pub(crate) expected: &'static str,
}

pub(crate) struct DecodeCase {
    pub(crate) name: &'static str,
    pub(crate) input: &'static [u8],
    pub(crate) expected: &'static [u8],
}
