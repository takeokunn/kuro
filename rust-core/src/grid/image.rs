//! Kitty Graphics Protocol image types
//!
//! Stores decoded image data, placement geometry, and completion
//! notifications for the Kitty terminal graphics protocol.

use crate::parser::kitty::ImageFormat;
use crate::parser::limits::MAX_APC_PAYLOAD_BYTES;
use std::collections::{HashMap, VecDeque};

/// Maximum pixel count for any single animation frame canvas or transmitted
/// region.
///
/// **`DoS` prevention:** the a=f composition path allocates a full RGBA canvas
/// (`pixel_count * 4` bytes) sized by the *declared* image dimensions and a
/// region buffer sized by the attacker-supplied `s=`/`v=` keys — neither is
/// bounded by the (tiny) payload that accompanies the sequence. Without this
/// cap a PTY could emit `a=f,s=65535,v=65535` and force a multi-gigabyte
/// allocation from a few bytes of input. We cap each buffer so its RGBA byte
/// size cannot exceed [`MAX_APC_PAYLOAD_BYTES`] (the same memory budget used
/// for direct/chunked transmission), i.e. 1 Mi pixels at 4 MiB.
const MAX_FRAME_CANVAS_PIXELS: usize = MAX_APC_PAYLOAD_BYTES / 4;

/// A single animation frame: a full-canvas RGBA pixel buffer plus its display gap.
///
/// Frames are always normalized to RGBA at the base image dimensions so that
/// region composition (a=f x/y/s/v) and alpha-blending have a uniform target.
#[derive(Debug, Clone)]
pub struct ImageFrame {
    /// Full-canvas RGBA pixels (4 bytes/pixel, `pixel_width * pixel_height` pixels)
    pub pixels: Vec<u8>,
    /// Display gap in milliseconds before advancing to the next frame (0 = use default)
    pub gap_ms: u32,
}

/// Animation playback state for a multi-frame image.
#[derive(Debug, Clone, Default)]
pub struct AnimationState {
    /// Whether playback is active (set by a=a,s=3)
    pub playing: bool,
    /// Remaining loop iterations; `None` = infinite (a=a,v=1), `Some(n)` = finite
    pub loop_count: Option<u32>,
    /// Currently displayed frame index (0-based)
    pub current_frame: usize,
}

/// Stored image data, always decoded to Rgb or Rgba (never stored as PNG).
///
/// The base `pixels` form frame 1. Additional animation frames (a=f) are stored
/// in `frames` as full-canvas RGBA buffers; `frames[0]` mirrors the base image.
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
    /// Animation frames (RGBA, full-canvas). Empty until the first a=f frame is added,
    /// at which point frame 1 (the base image) is materialized as `frames[0]`.
    pub frames: Vec<ImageFrame>,
    /// Animation playback state (a=a control)
    pub animation: AnimationState,
}

impl ImageData {
    /// Construct a still image (no animation frames yet).
    #[must_use]
    pub fn new(pixels: Vec<u8>, format: ImageFormat, pixel_width: u32, pixel_height: u32) -> Self {
        Self {
            pixels,
            format,
            pixel_width,
            pixel_height,
            frames: Vec::new(),
            animation: AnimationState::default(),
        }
    }

    /// Byte count of raw pixel data (base image + all animation frames)
    #[must_use]
    pub fn byte_count(&self) -> usize {
        self.pixels.len() + self.frames.iter().map(|f| f.pixels.len()).sum::<usize>()
    }

    /// Total pixels in one full canvas at the base image dimensions.
    #[must_use]
    fn canvas_pixel_count(&self) -> usize {
        (self.pixel_width as usize).saturating_mul(self.pixel_height as usize)
    }

    /// Convert the base image into a full-canvas RGBA buffer (frame 1).
    #[must_use]
    fn base_as_rgba(&self) -> Vec<u8> {
        rgba_from(&self.pixels, self.format, self.canvas_pixel_count())
    }

    /// Ensure `frames` is materialized with at least frame 1 (the base image).
    ///
    /// Called lazily the first time an animation frame (a=f) is added so that
    /// still images never pay the RGBA-canvas allocation cost.
    fn ensure_frames_initialized(&mut self) {
        if self.frames.is_empty() {
            let base = self.base_as_rgba();
            self.frames.push(ImageFrame {
                pixels: base,
                gap_ms: 0,
            });
        }
    }

    /// Compose a transmitted animation frame (a=f) into this image.
    ///
    /// `frame_pixels` is the region payload (already RGB/RGBA). `x`/`y` give the
    /// region top-left in pixels and `w`/`h` its size (0 = full canvas).
    /// `base_frame` (c=) selects a canvas to copy as the starting point; `edit_frame`
    /// (r=) composes onto an existing frame in place. `bg_color` (Y=) fills a fresh
    /// canvas. `replace` (X=1) overwrites instead of alpha-blending. `gap_ms` (z=)
    /// is the display gap. Returns the 1-based index of the affected frame.
    #[expect(
        clippy::too_many_arguments,
        reason = "mirrors the kitty a=f key set; grouping into a struct adds indirection without clarity"
    )]
    pub fn compose_frame(
        &mut self,
        frame_pixels: &[u8],
        frame_format: ImageFormat,
        x: u32,
        y: u32,
        w: u32,
        h: u32,
        base_frame: Option<u32>,
        edit_frame: Option<u32>,
        bg_color: u32,
        replace: bool,
        gap_ms: u32,
    ) -> Option<usize> {
        let canvas_px = self.canvas_pixel_count();
        let region_w = if w == 0 { self.pixel_width } else { w };
        let region_h = if h == 0 { self.pixel_height } else { h };
        let region_px = (region_w as usize).saturating_mul(region_h as usize);
        // DoS guard: refuse frames whose canvas or region RGBA buffer would
        // exceed the per-transfer memory budget. Both pixel counts derive from
        // attacker-controlled keys (declared image dims / a=f s=,v=) and are NOT
        // bounded by the tiny accompanying payload, so an unbounded allocation
        // would otherwise be possible (e.g. a=f,s=65535,v=65535).
        if canvas_px > MAX_FRAME_CANVAS_PIXELS || region_px > MAX_FRAME_CANVAS_PIXELS {
            return None;
        }

        self.ensure_frames_initialized();

        let region = rgba_from(frame_pixels, frame_format, region_px);

        if let Some(target) = edit_frame.map(|n| n.saturating_sub(1) as usize) {
            // Edit an existing frame in place.
            if target < self.frames.len() {
                self.frames[target].gap_ms = gap_ms;
                let mut canvas = std::mem::take(&mut self.frames[target].pixels);
                self.blit_region(&mut canvas, &region, x, y, region_w, region_h, replace);
                self.frames[target].pixels = canvas;
                return Some(target + 1);
            }
        }

        // Build a fresh frame canvas from the requested background.
        let mut canvas = match base_frame.map(|n| n.saturating_sub(1) as usize) {
            Some(idx) if idx < self.frames.len() => self.frames[idx].pixels.clone(),
            _ => solid_rgba_canvas(bg_color, canvas_px),
        };
        self.blit_region(&mut canvas, &region, x, y, region_w, region_h, replace);
        self.frames.push(ImageFrame {
            pixels: canvas,
            gap_ms,
        });
        Some(self.frames.len())
    }

    /// Blit an RGBA `region` into `canvas` at pixel offset (x, y).
    #[expect(
        clippy::too_many_arguments,
        reason = "region geometry (offset + size + mode) is irreducible; a struct adds indirection"
    )]
    fn blit_region(
        &self,
        canvas: &mut [u8],
        region: &[u8],
        x: u32,
        y: u32,
        region_w: u32,
        region_h: u32,
        replace: bool,
    ) {
        let cw = self.pixel_width as usize;
        let ch = self.pixel_height as usize;
        let rw = region_w as usize;
        let rh = region_h as usize;
        for ry in 0..rh {
            let cy = y as usize + ry;
            if cy >= ch {
                break;
            }
            for rx in 0..rw {
                let cx = x as usize + rx;
                if cx >= cw {
                    break;
                }
                let src = (ry * rw + rx) * 4;
                let dst = (cy * cw + cx) * 4;
                if src + 4 > region.len() || dst + 4 > canvas.len() {
                    continue;
                }
                if replace {
                    canvas[dst..dst + 4].copy_from_slice(&region[src..src + 4]);
                } else {
                    alpha_blend(&mut canvas[dst..dst + 4], &region[src..src + 4]);
                }
            }
        }
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

    /// Re-encode as base64-encoded PNG string (for Emacs FFI transfer).
    ///
    /// When the image has animation frames, the currently selected frame is
    /// rendered instead of the static base image.
    #[must_use]
    pub fn to_png_base64(&self) -> String {
        if let Some(frame) = self.frames.get(self.animation.current_frame) {
            return crate::util::base64::encode(&rgba_png_bytes(
                &frame.pixels,
                self.pixel_width,
                self.pixel_height,
            ));
        }
        crate::util::base64::encode(&self.to_png_bytes())
    }

    /// Number of animation frames (0 for a still image).
    #[must_use]
    pub fn frame_count(&self) -> usize {
        self.frames.len()
    }

    /// Render the frame at `idx` (0-based) as a base64 PNG, or empty if absent.
    #[must_use]
    pub fn frame_png_base64(&self, idx: usize) -> String {
        self.frames.get(idx).map_or_else(String::new, |frame| {
            crate::util::base64::encode(&rgba_png_bytes(
                &frame.pixels,
                self.pixel_width,
                self.pixel_height,
            ))
        })
    }

    /// Display gap (ms) for the frame at `idx`, or 0 if absent.
    #[must_use]
    pub fn frame_gap_ms(&self, idx: usize) -> u32 {
        self.frames.get(idx).map_or(0, |f| f.gap_ms)
    }

    /// Apply an a=a animation control to this image.
    pub fn apply_animation_control(
        &mut self,
        state: Option<u32>,
        loop_count: Option<u32>,
        current_frame: Option<u32>,
    ) {
        if let Some(s) = state {
            // 1=stop, 2=loading (treat as paused), 3=run/loop.
            self.animation.playing = s == 3;
        }
        if let Some(lc) = loop_count {
            // Kitty: v=1 means infinite; any other positive value is a finite count.
            self.animation.loop_count = if lc == 1 { None } else { Some(lc) };
        }
        if let Some(cf) = current_frame {
            let idx = (cf.saturating_sub(1)) as usize;
            if !self.frames.is_empty() {
                self.animation.current_frame = idx.min(self.frames.len() - 1);
            }
        }
    }
}

/// Encode RGBA pixels of the given dimensions as PNG bytes.
fn rgba_png_bytes(pixels: &[u8], width: u32, height: u32) -> Vec<u8> {
    let mut buf = Vec::new();
    {
        let cursor = std::io::Cursor::new(&mut buf);
        let mut encoder = png::Encoder::new(cursor, width, height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        if let Ok(mut writer) = encoder.write_header() {
            let _ = writer.write_image_data(pixels);
        }
    }
    buf
}

/// Convert RGB/RGBA `src` to a full-canvas RGBA buffer of exactly `px` pixels.
///
/// Missing pixels are filled transparent; RGB pixels gain an opaque alpha.
fn rgba_from(src: &[u8], format: ImageFormat, px: usize) -> Vec<u8> {
    let mut out = vec![0u8; px * 4];
    match format {
        ImageFormat::Rgba => {
            let n = src.len().min(out.len());
            out[..n].copy_from_slice(&src[..n]);
        }
        ImageFormat::Rgb => {
            for i in 0..px {
                let s = i * 3;
                let d = i * 4;
                if s + 3 > src.len() {
                    break;
                }
                out[d] = src[s];
                out[d + 1] = src[s + 1];
                out[d + 2] = src[s + 2];
                out[d + 3] = 0xFF;
            }
        }
    }
    out
}

/// Build a solid RGBA canvas of `px` pixels filled with `color` (0xRRGGBBAA).
fn solid_rgba_canvas(color: u32, px: usize) -> Vec<u8> {
    let [r, g, b, a] = color.to_be_bytes();
    let mut out = Vec::with_capacity(px * 4);
    for _ in 0..px {
        out.extend_from_slice(&[r, g, b, a]);
    }
    out
}

/// Alpha-blend `src` (RGBA) over `dst` (RGBA) in place (src-over).
fn alpha_blend(dst: &mut [u8], src: &[u8]) {
    let sa = u32::from(src[3]);
    if sa == 0 {
        return;
    }
    if sa == 255 {
        dst.copy_from_slice(src);
        return;
    }
    let ia = 255 - sa;
    for c in 0..3 {
        let blended = (u32::from(src[c]) * sa + u32::from(dst[c]) * ia) / 255;
        dst[c] = blended as u8;
    }
    let da = u32::from(dst[3]);
    dst[3] = (sa + da * ia / 255) as u8;
}

/// A placed image instance on the terminal grid
#[derive(Debug, Clone, Default)]
pub struct ImagePlacement {
    /// ID of the stored image being placed
    pub image_id: u32,
    /// Optional placement ID (Kitty `p=` param) for targeted deletion via `a=d,p=`
    pub placement_id: Option<u32>,
    /// Terminal row where the image is placed (0-indexed)
    pub row: usize,
    /// Terminal column where the image is placed (0-indexed)
    pub col: usize,
    /// Width of the placement in terminal columns
    pub display_cols: u32,
    /// Height of the placement in terminal rows
    pub display_rows: u32,
    /// Z-index (Kitty `z=` key, signed). Larger values draw on top; negative
    /// values draw behind text. Default 0. Used for `a=d,d=z`/`a=d,d=q` deletion
    /// and to control stacking order (placements are kept sorted by `z_index`).
    pub z_index: i32,
    /// Cell-internal pixel X offset within the top-left cell (Kitty `X=` key in
    /// the place/transmit context). Surfaced to Emacs so the image can be drawn
    /// shifted inside its anchor cell.
    pub pixel_x_offset: u32,
    /// Cell-internal pixel Y offset within the top-left cell (Kitty `Y=` key in
    /// the place/transmit context).
    pub pixel_y_offset: u32,
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
    /// Cell-internal pixel X offset (Kitty `X=` key); 0 when unset.
    pub pixel_x_offset: u32,
    /// Cell-internal pixel Y offset (Kitty `Y=` key); 0 when unset.
    pub pixel_y_offset: u32,
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

    fn rewrite_placements<F>(&mut self, f: F)
    where
        F: FnMut(ImagePlacement) -> Option<ImagePlacement>,
    {
        self.placements = std::mem::take(&mut self.placements)
            .into_iter()
            .filter_map(f)
            .collect();
    }

    fn retain_placements<F>(&mut self, mut predicate: F)
    where
        F: FnMut(&ImagePlacement) -> bool,
    {
        self.rewrite_placements(|placement| predicate(&placement).then_some(placement));
    }

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

    /// Returns true when an image with `image_id` is currently stored.
    ///
    /// Used by the Unicode-placeholder region walk to exclude *orphan*
    /// placeholders (cells that reference an image id no longer in the store) so
    /// they are never emitted as renderable tiles.
    #[inline]
    #[must_use]
    pub fn contains_image(&self, image_id: u32) -> bool {
        self.images.contains_key(&image_id)
    }

    /// Return the image as a base64-encoded PNG string.
    /// Returns an empty string if the `image_id` is not found (orphan reference).
    #[must_use]
    pub fn get_image_png_base64(&self, image_id: u32) -> String {
        self.images
            .get(&image_id)
            .map_or_else(String::new, ImageData::to_png_base64)
    }

    /// Compose an animation frame (a=f) onto the image identified by `image_id`.
    ///
    /// Returns the 1-based index of the affected frame, or `None` if the image is
    /// unknown. The store's byte accounting is updated to reflect the new frame data.
    #[expect(
        clippy::too_many_arguments,
        reason = "forwards the kitty a=f key set to ImageData::compose_frame"
    )]
    pub fn add_frame(
        &mut self,
        image_id: u32,
        frame_pixels: &[u8],
        frame_format: ImageFormat,
        x: u32,
        y: u32,
        w: u32,
        h: u32,
        base_frame: Option<u32>,
        edit_frame: Option<u32>,
        bg_color: u32,
        replace: bool,
        gap_ms: u32,
    ) -> Option<usize> {
        let data = self.images.get_mut(&image_id)?;
        let before = data.byte_count();
        let frame_no = data.compose_frame(
            frame_pixels,
            frame_format,
            x,
            y,
            w,
            h,
            base_frame,
            edit_frame,
            bg_color,
            replace,
            gap_ms,
        )?;
        let after = data.byte_count();
        self.current_bytes = self.current_bytes.saturating_sub(before) + after;
        self.touch_lru(image_id);
        Some(frame_no)
    }

    /// Apply an a=a animation control to the image identified by `image_id`.
    /// Returns true if the image exists and the control was applied.
    pub fn set_animation(
        &mut self,
        image_id: u32,
        state: Option<u32>,
        loop_count: Option<u32>,
        current_frame: Option<u32>,
    ) -> bool {
        match self.images.get_mut(&image_id) {
            Some(data) => {
                data.apply_animation_control(state, loop_count, current_frame);
                true
            }
            None => false,
        }
    }

    /// Number of animation frames stored for `image_id` (0 if still or unknown).
    #[must_use]
    pub fn frame_count(&self, image_id: u32) -> usize {
        self.images.get(&image_id).map_or(0, ImageData::frame_count)
    }

    /// Render frame `idx` of `image_id` as a base64 PNG (empty if absent).
    #[must_use]
    pub fn frame_png_base64(&self, image_id: u32, idx: usize) -> String {
        self.images
            .get(&image_id)
            .map_or_else(String::new, |d| d.frame_png_base64(idx))
    }

    /// Display gap (ms) of frame `idx` for `image_id` (0 if absent).
    #[must_use]
    pub fn frame_gap_ms(&self, image_id: u32, idx: usize) -> u32 {
        self.images
            .get(&image_id)
            .map_or(0, |d| d.frame_gap_ms(idx))
    }

    /// Return `(playing, current_frame_1based, loop_count_or_0)` for `image_id`.
    /// `loop_count` of 0 means infinite. Returns `None` if the image is unknown.
    #[must_use]
    pub fn animation_state(&self, image_id: u32) -> Option<(bool, usize, u32)> {
        self.images.get(&image_id).map(|d| {
            (
                d.animation.playing,
                d.animation.current_frame + 1,
                d.animation.loop_count.unwrap_or(0),
            )
        })
    }

    /// Move `image_id` to the most-recently-used position in the LRU order.
    fn touch_lru(&mut self, image_id: u32) {
        if self.lru_order.back() != Some(&image_id) {
            self.lru_order.retain(|&i| i != image_id);
            self.lru_order.push_back(image_id);
        }
    }

    /// Add a placement and return an `ImageNotification` (or None if `image_id` unknown).
    ///
    /// Placements are stored in ascending `z_index` order so that later rendering
    /// honors the Kitty `z=` stacking key: a placement with a larger `z_index`
    /// draws on top of (after) one with a smaller `z_index`. Insertion uses a
    /// stable position so equal-z placements preserve arrival order.
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
            pixel_x_offset: placement.pixel_x_offset,
            pixel_y_offset: placement.pixel_y_offset,
        };
        // Insert keeping the vector sorted by z_index (stable for ties).
        let pos = self
            .placements
            .partition_point(|p| p.z_index <= placement.z_index);
        self.placements.insert(pos, placement);
        Some(notif)
    }

    /// Build re-display notifications for every existing placement of `image_id`.
    ///
    /// Used after an animation frame is composed or the current frame changes so
    /// Emacs redraws the already-placed image with its new pixels.
    #[must_use]
    pub fn notifications_for_image(&self, image_id: u32) -> Vec<ImageNotification> {
        self.placements
            .iter()
            .filter(|p| p.image_id == image_id)
            .map(|p| ImageNotification {
                image_id: p.image_id,
                row: p.row,
                col: p.col,
                cell_width: p.display_cols,
                cell_height: p.display_rows,
                pixel_x_offset: p.pixel_x_offset,
                pixel_y_offset: p.pixel_y_offset,
            })
            .collect()
    }

    /// Clear all image placements (called on ED mode 2/3, screen clear)
    pub fn clear_all_placements(&mut self) {
        self.placements.clear();
    }

    /// Number of active placements (test/introspection helper).
    #[must_use]
    pub fn placement_count(&self) -> usize {
        self.placements.len()
    }

    /// The `z_index` values of all placements, in stored (ascending-z) order.
    /// Test/introspection helper for verifying z-ordering.
    #[must_use]
    pub fn placement_z_indices(&self) -> Vec<i32> {
        self.placements.iter().map(|p| p.z_index).collect()
    }

    /// Shift all placement rows up by `n` lines (called on terminal `scroll_up`).
    /// Placements that scroll off the top (row < n) are discarded.
    pub fn scroll_up(&mut self, n: usize) {
        self.rewrite_placements(|mut placement| {
            if placement.row < n {
                None
            } else {
                placement.row -= n;
                Some(placement)
            }
        });
    }

    /// Shift all placement rows down by `n` lines (called on terminal `scroll_down`).
    /// Placements are clamped to `max_row - 1` rather than discarded.
    pub fn scroll_down(&mut self, n: usize, max_row: usize) {
        self.rewrite_placements(|mut placement| {
            placement.row = (placement.row + n).min(max_row.saturating_sub(1));
            Some(placement)
        });
    }

    /// Delete an image and all its placements by ID
    pub fn delete_by_id(&mut self, image_id: u32) {
        if let Some(data) = self.images.remove(&image_id) {
            self.current_bytes = self.current_bytes.saturating_sub(data.byte_count());
            self.lru_order.retain(|&i| i != image_id);
        }
        self.retain_placements(|placement| placement.image_id != image_id);
    }

    /// Delete placements matching both image ID and placement ID (Kitty `a=d,p=`)
    pub fn delete_by_placement(&mut self, image_id: u32, placement_id: u32) {
        self.retain_placements(|placement| {
            placement.image_id != image_id || placement.placement_id != Some(placement_id)
        });
    }

    /// Delete all placements whose top-left row equals `row` (Kitty `a=d,d=y`)
    pub fn delete_by_row(&mut self, row: usize) {
        self.retain_placements(|placement| placement.row != row);
    }

    /// Delete all placements whose top-left column equals `col` (Kitty `a=d,d=x`)
    pub fn delete_by_col(&mut self, col: usize) {
        self.retain_placements(|placement| placement.col != col);
    }

    /// Remove the underlying image data (and byte accounting / LRU) for every
    /// `image_id` that currently has at least one placement matched by
    /// `should_delete`, then drop those placements.
    ///
    /// Used by the uppercase Kitty delete targets (`A`/`I`/`N`/`C`/`P`/`Q`/`X`/
    /// `Y`/`Z`/`R`) which "also free the stored image data", not just the
    /// placement. The image is freed only when a matching placement exists.
    fn delete_placements_freeing<F>(&mut self, should_delete: F)
    where
        F: Fn(&ImagePlacement) -> bool,
    {
        // Collect distinct image ids whose placements are being removed.
        let mut freed_ids: Vec<u32> = Vec::new();
        for placement in &self.placements {
            if should_delete(placement) && !freed_ids.contains(&placement.image_id) {
                freed_ids.push(placement.image_id);
            }
        }
        self.retain_placements(|placement| !should_delete(placement));
        for id in freed_ids {
            // delete_by_id is idempotent and also clears any *other* placements
            // of this image; that is correct — freeing image data invalidates
            // every placement that references it.
            self.delete_by_id(id);
        }
    }

    /// Generic placement deletion. `free_data` selects the uppercase semantics
    /// (also free the backing image) vs lowercase (drop placements only).
    fn delete_matching<F>(&mut self, free_data: bool, predicate: F)
    where
        F: Fn(&ImagePlacement) -> bool,
    {
        if free_data {
            self.delete_placements_freeing(predicate);
        } else {
            self.retain_placements(|placement| !predicate(placement));
        }
    }

    /// Delete every placement (Kitty `a=d,d=a`/`A`). When `free_data`, also free
    /// the backing image data for every image that had a placement.
    pub fn delete_all(&mut self, free_data: bool) {
        if free_data {
            self.delete_placements_freeing(|_| true);
        } else {
            self.placements.clear();
        }
    }

    /// Delete placements by image id (Kitty `a=d,d=i`/`I`). Lowercase drops the
    /// placements (and, matching kitty, the image); uppercase additionally frees
    /// the image data. Both end with the image gone, so they coincide here, but
    /// `free_data` is threaded for symmetry and clarity.
    pub fn delete_id(&mut self, image_id: u32, _free_data: bool) {
        self.delete_by_id(image_id);
    }

    /// Delete the newest placement(s) referencing the highest stored image
    /// number (Kitty `a=d,d=n`/`N`, key `I=` selects the image number). With no
    /// explicit number, the most-recently-stored image (`next_auto_id - 1`,
    /// falling back to the max known id) is used.
    pub fn delete_newest(&mut self, image_number: Option<u32>, free_data: bool) {
        let target = match image_number {
            Some(n) => n,
            None => {
                // Highest image id currently stored.
                match self.images.keys().copied().max() {
                    Some(id) => id,
                    None => return,
                }
            }
        };
        self.delete_matching(free_data, |p| p.image_id == target);
    }

    /// Delete placements intersecting the cursor cell (Kitty `a=d,d=c`/`C`).
    pub fn delete_at_cursor(&mut self, row: usize, col: usize, free_data: bool) {
        self.delete_at_cell(row, col, free_data);
    }

    /// Delete placements intersecting cell (`row`,`col`) (Kitty `a=d,d=p`/`P`,
    /// keys `x=`column `y=`row). A placement intersects the cell when the cell
    /// falls inside its `display_cols`×`display_rows` rectangle anchored at its
    /// top-left.
    pub fn delete_at_cell(&mut self, row: usize, col: usize, free_data: bool) {
        self.delete_matching(free_data, |p| placement_covers(p, row, col));
    }

    /// Delete placements intersecting cell (`row`,`col`) with the given
    /// `z_index` (Kitty `a=d,d=q`/`Q`, keys `x=`,`y=`,`z=`).
    pub fn delete_at_cell_with_z(&mut self, row: usize, col: usize, z: i32, free_data: bool) {
        self.delete_matching(free_data, |p| {
            p.z_index == z && placement_covers(p, row, col)
        });
    }

    /// Delete placements intersecting column `col` (Kitty `a=d,d=x`/`X`, key
    /// `x=`). Intersection spans the placement's full `display_cols` width.
    pub fn delete_intersecting_col(&mut self, col: usize, free_data: bool) {
        self.delete_matching(free_data, |p| placement_covers_col(p, col));
    }

    /// Delete placements intersecting row `row` (Kitty `a=d,d=y`/`Y`, key `y=`).
    /// Intersection spans the placement's full `display_rows` height.
    pub fn delete_intersecting_row(&mut self, row: usize, free_data: bool) {
        self.delete_matching(free_data, |p| placement_covers_row(p, row));
    }

    /// Delete placements with the given `z_index` (Kitty `a=d,d=z`/`Z`, key
    /// `z=`).
    pub fn delete_by_z(&mut self, z: i32, free_data: bool) {
        self.delete_matching(free_data, |p| p.z_index == z);
    }

    /// Delete placements whose image id is in the inclusive range
    /// `min..=max` (Kitty `a=d,d=r`/`R`, keys `x=`min `y=`max).
    pub fn delete_id_range(&mut self, min: u32, max: u32, free_data: bool) {
        self.delete_matching(free_data, |p| p.image_id >= min && p.image_id <= max);
    }
}

/// True when cell (`row`,`col`) falls inside the placement's display rectangle.
#[inline]
fn placement_covers(p: &ImagePlacement, row: usize, col: usize) -> bool {
    placement_covers_row(p, row) && placement_covers_col(p, col)
}

/// True when `col` falls inside the placement's horizontal span.
#[inline]
fn placement_covers_col(p: &ImagePlacement, col: usize) -> bool {
    let span = (p.display_cols.max(1)) as usize;
    col >= p.col && col < p.col + span
}

/// True when `row` falls inside the placement's vertical span.
#[inline]
fn placement_covers_row(p: &ImagePlacement, row: usize) -> bool {
    let span = (p.display_rows.max(1)) as usize;
    row >= p.row && row < p.row + span
}

#[cfg(test)]
#[path = "image/tests.rs"]
mod tests;
