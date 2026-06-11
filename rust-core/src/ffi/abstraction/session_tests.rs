#[cfg(test)]
mod tests {
    use super::advance_with_budget;
    use crate::ffi::codec::COLOR_DEFAULT_SENTINEL;

    fn make_core() -> crate::TerminalCore {
        crate::TerminalCore::new(24, 80)
    }

    #[test]
    fn test_advance_with_budget_under_budget() {
        let mut core = make_core();
        let mut budget = 100usize;
        let mut overflow = Vec::new();
        advance_with_budget(&mut core, b"hello", &mut budget, &mut overflow);
        assert_eq!(budget, 95);
        assert!(overflow.is_empty());
    }

    #[test]
    fn test_advance_with_budget_over_budget() {
        let mut core = make_core();
        let mut budget = 3usize;
        let mut overflow = Vec::new();
        advance_with_budget(&mut core, b"hello", &mut budget, &mut overflow);
        assert_eq!(budget, 0);
        assert_eq!(overflow, b"lo");
    }

    #[test]
    fn test_advance_with_budget_exact_fit() {
        let mut core = make_core();
        let mut budget = 5usize;
        let mut overflow = Vec::new();
        advance_with_budget(&mut core, b"hello", &mut budget, &mut overflow);
        assert_eq!(budget, 0);
        assert!(overflow.is_empty(), "exact fit must not produce overflow");
    }

    #[test]
    fn test_advance_with_budget_empty_data_is_noop() {
        let mut core = make_core();
        let mut budget = 100usize;
        let mut overflow = Vec::new();
        advance_with_budget(&mut core, &[], &mut budget, &mut overflow);
        assert_eq!(budget, 100, "budget must be unchanged for empty data");
        assert!(overflow.is_empty());
    }

    #[test]
    fn test_color_default_sentinel_is_outside_rgb_space() {
        // The sentinel must be outside the 24-bit RGB space (0x00FF_FFFF is the max).
        // Top byte is 0xFF, which encode_color never produces for a real color.
        assert_eq!(COLOR_DEFAULT_SENTINEL, 0xFF00_0000);
        const { assert!(COLOR_DEFAULT_SENTINEL > 0x00FF_FFFF) };
    }

    #[test]
    fn test_get_default_colors_unset_returns_sentinel() {
        use super::{SessionState, TerminalSession};
        let session = TerminalSession {
            core: crate::TerminalCore::new(24, 80),
            #[cfg(unix)]
            pty: None,
            command: String::new(),
            state: SessionState::Bound,
            #[cfg(unix)]
            pending_input: Vec::new(),
            row_hashes: Vec::new(),
            palette_epoch: 0,
            was_alt_screen: false,
            encode_pool: crate::ffi::codec::EncodePool::new(),
            dirty_scratch: Vec::new(),
            texts_scratch: Vec::new(),
            buf_scratch: Vec::new(),
        };
        let (fg, bg, cursor) = session.get_default_colors();
        // Before any OSC 10/11/12, all three are unset → sentinel
        assert_eq!(fg, COLOR_DEFAULT_SENTINEL);
        assert_eq!(bg, COLOR_DEFAULT_SENTINEL);
        assert_eq!(cursor, COLOR_DEFAULT_SENTINEL);
    }
}
