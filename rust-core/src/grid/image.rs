//! Kitty Graphics Protocol image types
//!
//! Stores decoded image data, placement geometry, and completion
//! notifications for the Kitty terminal graphics protocol.

use crate::parser::kitty::ImageFormat;
use std::collections::{HashMap, VecDeque};

/// Stored image data, always decoded to Rgb or Rgba (never stored as PNG)
#[derive(Debug, Clone)]
pub struct ImageData {
    /// Raw pixel bytes in the specified format
    pub pixels: Vec<u8>,
    /// Pixel format: Rgb (3 bytes/pixel) or Rgba (4 bytes/pixel)
    pub format: ImageFormat,
    /// Image width in pixels
    pub pixel_width: u32,
    /// Image height in pixels
    pub pixel_height: u32,
}

impl ImageData {
    /// Byte count of raw pixel data
    #[must_use]
    pub const fn byte_count(&self) -> usize {
        self.pixels.len()
    }

    /// Re-encode raw pixels as PNG bytes for FFI transfer
    fn to_png_bytes(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        {
            let cursor = std::io::Cursor::new(&mut buf);
            let mut encoder = png::Encoder::new(cursor, self.pixel_width, self.pixel_height);
            encoder.set_color(match self.format {
                ImageFormat::Rgb => png::ColorType::Rgb,
                ImageFormat::Rgba => png::ColorType::Rgba,
            });
            encoder.set_depth(png::BitDepth::Eight);
            if let Ok(mut writer) = encoder.write_header() {
                let _ = writer.write_image_data(&self.pixels);
            }
        }
        buf
    }

    /// Re-encode as base64-encoded PNG string (for Emacs FFI transfer)
    #[must_use]
    pub fn to_png_base64(&self) -> String {
        use base64::engine::general_purpose::STANDARD as BASE64_STANDARD;
        use base64::Engine as _;
        BASE64_STANDARD.encode(self.to_png_bytes())
    }
}

/// A placed image instance on the terminal grid
#[derive(Debug, Clone)]
pub struct ImagePlacement {
    /// ID of the stored image being placed
    pub image_id: u32,
    /// Terminal row where the image is placed (0-indexed)
    pub row: usize,
    /// Terminal column where the image is placed (0-indexed)
    pub col: usize,
    /// Width of the placement in terminal columns
    pub display_cols: u32,
    /// Height of the placement in terminal rows
    pub display_rows: u32,
}

/// Notification emitted to Elisp when an image is placed on the terminal
#[derive(Debug, Clone)]
pub struct ImageNotification {
    /// ID of the image that was placed
    pub image_id: u32,
    /// Terminal row of the placement (0-indexed)
    pub row: usize,
    /// Terminal column of the placement (0-indexed)
    pub col: usize,
    /// Width of the placement in terminal columns
    pub cell_width: u32,
    /// Height of the placement in terminal rows
    pub cell_height: u32,
}

/// LRU image store with 256 MB capacity cap
#[derive(Debug)]
pub struct GraphicsStore {
    images: HashMap<u32, ImageData>,
    /// LRU tracking: front = oldest, back = most recently used
    lru_order: VecDeque<u32>,
    max_bytes: usize,
    current_bytes: usize,
    placements: Vec<ImagePlacement>,
    /// Auto-increment counter for images stored without an explicit ID
    next_auto_id: u32,
}

impl Default for GraphicsStore {
    fn default() -> Self {
        Self::new()
    }
}

impl GraphicsStore {
    const MAX_BYTES: usize = 256 * 1024 * 1024; // 256 MB

    /// Create a new empty graphics store with the default 256 MB capacity cap
    #[must_use]
    pub fn new() -> Self {
        Self {
            images: HashMap::new(),
            lru_order: VecDeque::new(),
            max_bytes: Self::MAX_BYTES,
            current_bytes: 0,
            placements: Vec::new(),
            next_auto_id: 1,
        }
    }

    /// Store an image, LRU-evicting old images if over capacity.
    /// Returns the actual image ID used (auto-assigned if `id` is None).
    pub fn store_image(&mut self, id: Option<u32>, data: ImageData) -> u32 {
        let actual_id = id.unwrap_or_else(|| {
            let id = self.next_auto_id;
            self.next_auto_id = self.next_auto_id.wrapping_add(1).max(1);
            id
        });

        let byte_count = data.byte_count();

        // Remove old entry with same ID if it exists
        if let Some(old) = self.images.remove(&actual_id) {
            self.current_bytes = self.current_bytes.saturating_sub(old.byte_count());
            self.lru_order.retain(|&i| i != actual_id);
        }

        // Evict oldest images while over capacity
        while self.current_bytes + byte_count > self.max_bytes && !self.lru_order.is_empty() {
            if let Some(old_id) = self.lru_order.pop_front() {
                if let Some(old_data) = self.images.remove(&old_id) {
                    self.current_bytes = self.current_bytes.saturating_sub(old_data.byte_count());
                    self.placements.retain(|p| p.image_id != old_id);
                }
            }
        }

        self.current_bytes += byte_count;
        self.images.insert(actual_id, data);
        self.lru_order.push_back(actual_id);
        actual_id
    }

    /// Return the image as a base64-encoded PNG string.
    /// Returns an empty string if the `image_id` is not found (orphan reference).
    #[must_use]
    pub fn get_image_png_base64(&self, image_id: u32) -> String {
        self.images
            .get(&image_id)
            .map_or_else(String::new, ImageData::to_png_base64)
    }

    /// Add a placement and return an `ImageNotification` (or None if `image_id` unknown)
    pub fn add_placement(&mut self, placement: ImagePlacement) -> Option<ImageNotification> {
        if !self.images.contains_key(&placement.image_id) {
            return None;
        }
        let notif = ImageNotification {
            image_id: placement.image_id,
            row: placement.row,
            col: placement.col,
            cell_width: placement.display_cols,
            cell_height: placement.display_rows,
        };
        self.placements.push(placement);
        Some(notif)
    }

    /// Clear all image placements (called on ED mode 2/3, screen clear)
    pub fn clear_all_placements(&mut self) {
        self.placements.clear();
    }

    /// Shift all placement rows up by `n` lines (called on terminal `scroll_up`).
    /// Placements that scroll off the top (row < n) are discarded.
    pub fn scroll_up(&mut self, n: usize) {
        self.placements = std::mem::take(&mut self.placements)
            .into_iter()
            .filter_map(|mut p| {
                if p.row < n {
                    None
                } else {
                    p.row -= n;
                    Some(p)
                }
            })
            .collect();
    }

    /// Shift all placement rows down by `n` lines (called on terminal `scroll_down`).
    /// Placements are clamped to `max_row - 1` rather than discarded.
    pub fn scroll_down(&mut self, n: usize, max_row: usize) {
        for p in &mut self.placements {
            p.row = (p.row + n).min(max_row.saturating_sub(1));
        }
    }

    /// Delete an image and all its placements by ID
    pub fn delete_by_id(&mut self, image_id: u32) {
        if let Some(data) = self.images.remove(&image_id) {
            self.current_bytes = self.current_bytes.saturating_sub(data.byte_count());
            self.lru_order.retain(|&i| i != image_id);
        }
        self.placements.retain(|p| p.image_id != image_id);
    }
}
