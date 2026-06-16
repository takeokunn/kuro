use crate::types::osc::{OscData, PromptMark, PromptMarkEvent};
use crate::types::color::Color;

pub(crate) fn prompt_mark_event(
    mark: PromptMark,
    row: usize,
    col: usize,
    exit_code: Option<i32>,
) -> PromptMarkEvent {
    PromptMarkEvent {
        mark,
        row,
        col,
        exit_code,
        aid: None,
        duration_ms: None,
        err_path: None,
    }
}

pub(crate) fn osc_data_with_default_fg(color: Color) -> OscData {
    OscData {
        default_fg: Some(color),
        ..Default::default()
    }
}
