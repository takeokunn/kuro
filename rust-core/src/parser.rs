//! VTE Parser integration

pub mod apc;
pub mod csi;
pub mod dcs;
pub mod dec_private;
pub mod erase;
pub mod insert_delete;
pub mod kitty;
pub(crate) mod limits;
pub mod osc;
pub mod osc_protocol;
pub mod scroll;
pub mod sgr;
pub mod sixel;
pub mod tabs;
pub mod vte_handler;
