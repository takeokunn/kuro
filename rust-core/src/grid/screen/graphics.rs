//! Graphics store access methods for Screen

use super::{Screen, GraphicsStore};

impl Screen {
    /// Get reference to the active screen's graphics store
    #[must_use] 
    pub fn active_graphics(&self) -> &GraphicsStore {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_ref() {
                return &alt.graphics;
            }
        }
        &self.graphics
    }

    /// Get mutable reference to the active screen's graphics store
    pub fn active_graphics_mut(&mut self) -> &mut GraphicsStore {
        if self.is_alternate_active {
            if let Some(alt) = self.alternate_screen.as_mut() {
                return &mut alt.graphics;
            }
        }
        &mut self.graphics
    }

    /// Get image from any screen (primary first, then active if alternate)
    #[must_use] 
    pub fn get_image_png_base64(&self, image_id: u32) -> String {
        // Check primary screen's store
        let result = self.graphics.get_image_png_base64(image_id);
        if !result.is_empty() {
            return result;
        }
        // If alternate is active, also check alternate screen's store
        if self.is_alternate_active {
            if let Some(alt) = &self.alternate_screen {
                return alt.graphics.get_image_png_base64(image_id);
            }
        }
        String::new()
    }
}
