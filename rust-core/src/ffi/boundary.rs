//! Strictly typed boundary values for legacy FFI entry points.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct FfiWindowDimension(u16);

impl FfiWindowDimension {
    pub(crate) fn parse(value: i64) -> Option<Self> {
        let dimension = u16::try_from(value).ok()?;
        (dimension > 0).then_some(Self(dimension))
    }

    pub(crate) const fn get(self) -> u16 {
        self.0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct FfiWindowSize {
    rows: FfiWindowDimension,
    cols: FfiWindowDimension,
}

impl FfiWindowSize {
    pub(crate) fn parse(rows: i64, cols: i64) -> Option<Self> {
        Some(Self {
            rows: FfiWindowDimension::parse(rows)?,
            cols: FfiWindowDimension::parse(cols)?,
        })
    }

    pub(crate) const fn rows(self) -> u16 {
        self.rows.get()
    }

    pub(crate) const fn cols(self) -> u16 {
        self.cols.get()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct FfiScrollbackQueryLimit(usize);

impl FfiScrollbackQueryLimit {
    pub(crate) fn parse(max_lines: i64) -> Option<Self> {
        if max_lines == 0 {
            Some(Self(usize::MAX))
        } else {
            usize::try_from(max_lines).ok().map(Self)
        }
    }

    pub(crate) const fn get(self) -> usize {
        self.0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct FfiScrollbackMaxLines(usize);

impl FfiScrollbackMaxLines {
    pub(crate) fn parse(max_lines: i64) -> Option<Self> {
        usize::try_from(max_lines).ok().map(Self)
    }

    pub(crate) const fn get(self) -> usize {
        self.0
    }
}

#[cfg(test)]
mod tests {
    use super::{
        FfiScrollbackMaxLines, FfiScrollbackQueryLimit, FfiWindowDimension, FfiWindowSize,
    };

    #[test]
    fn window_dimension_accepts_non_zero_u16_range() {
        assert_eq!(
            FfiWindowDimension::parse(1).map(FfiWindowDimension::get),
            Some(1)
        );
        assert_eq!(
            FfiWindowDimension::parse(i64::from(u16::MAX)).map(FfiWindowDimension::get),
            Some(u16::MAX)
        );
    }

    #[test]
    fn window_dimension_rejects_zero_negative_and_overflow() {
        assert_eq!(FfiWindowDimension::parse(0), None);
        assert_eq!(FfiWindowDimension::parse(-1), None);
        assert_eq!(FfiWindowDimension::parse(i64::from(u16::MAX) + 1), None);
    }

    #[test]
    fn window_size_rejects_any_invalid_dimension() {
        assert!(FfiWindowSize::parse(24, 80).is_some());
        assert_eq!(FfiWindowSize::parse(0, 80), None);
        assert_eq!(FfiWindowSize::parse(24, 0), None);
        assert_eq!(FfiWindowSize::parse(-1, 80), None);
        assert_eq!(FfiWindowSize::parse(24, i64::from(u16::MAX) + 1), None);
    }

    #[test]
    fn scrollback_query_zero_means_all_and_negative_is_invalid() {
        assert_eq!(
            FfiScrollbackQueryLimit::parse(0).map(FfiScrollbackQueryLimit::get),
            Some(usize::MAX)
        );
        assert_eq!(
            FfiScrollbackQueryLimit::parse(42).map(FfiScrollbackQueryLimit::get),
            Some(42)
        );
        assert_eq!(FfiScrollbackQueryLimit::parse(-1), None);
    }

    #[test]
    fn scrollback_max_lines_allows_zero_but_rejects_negative() {
        assert_eq!(
            FfiScrollbackMaxLines::parse(0).map(FfiScrollbackMaxLines::get),
            Some(0)
        );
        assert_eq!(
            FfiScrollbackMaxLines::parse(42).map(FfiScrollbackMaxLines::get),
            Some(42)
        );
        assert_eq!(FfiScrollbackMaxLines::parse(-1), None);
    }
}
