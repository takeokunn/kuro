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
pub(crate) mod png_decode {
    //! Shared inline PNG decoder for terminal graphics protocols.

    use std::io::Cursor;

    use super::{kitty::ImageFormat, limits::MAX_APC_PAYLOAD_BYTES};

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub(crate) enum PngDecodeError {
        InvalidHeader,
        DecodeBudgetExceeded,
        InvalidFrame,
        UnsupportedColorLayout,
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub(crate) struct PngDimensions {
        width: u32,
        height: u32,
        pixels: usize,
    }

    impl PngDimensions {
        fn new(width: u32, height: u32) -> Result<Self, PngDecodeError> {
            if width == 0 || height == 0 {
                return Err(PngDecodeError::InvalidHeader);
            }

            let width_len =
                usize::try_from(width).map_err(|_| PngDecodeError::DecodeBudgetExceeded)?;
            let height_len =
                usize::try_from(height).map_err(|_| PngDecodeError::DecodeBudgetExceeded)?;
            let pixels = width_len
                .checked_mul(height_len)
                .ok_or(PngDecodeError::DecodeBudgetExceeded)?;

            Ok(Self {
                width,
                height,
                pixels,
            })
        }

        pub(crate) fn width(self) -> u32 {
            self.width
        }

        pub(crate) fn height(self) -> u32 {
            self.height
        }

        fn byte_len(self, bytes_per_pixel: usize) -> Result<usize, PngDecodeError> {
            if bytes_per_pixel == 0 {
                return Err(PngDecodeError::UnsupportedColorLayout);
            }
            self.pixels
                .checked_mul(bytes_per_pixel)
                .ok_or(PngDecodeError::DecodeBudgetExceeded)
        }
    }

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    struct PngDecodeBudget {
        max_decoded_bytes: usize,
    }

    impl PngDecodeBudget {
        const fn inline_image() -> Self {
            Self {
                max_decoded_bytes: MAX_APC_PAYLOAD_BYTES,
            }
        }

        fn check_dimensions(self, dimensions: PngDimensions) -> Result<(), PngDecodeError> {
            let worst_case_rgba_len = dimensions.byte_len(4)?;
            self.check_normalized_size(worst_case_rgba_len)
        }

        fn check_output_buffer_size(self, output_buffer_size: usize) -> Result<(), PngDecodeError> {
            self.check_normalized_size(output_buffer_size)
        }

        fn check_normalized_size(self, byte_len: usize) -> Result<(), PngDecodeError> {
            if byte_len > self.max_decoded_bytes {
                return Err(PngDecodeError::DecodeBudgetExceeded);
            }
            Ok(())
        }
    }

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub(crate) struct DecodedPng {
        pixels: Vec<u8>,
        format: ImageFormat,
        dimensions: PngDimensions,
    }

    impl DecodedPng {
        pub(crate) fn into_pixels_and_format(self) -> (Vec<u8>, ImageFormat) {
            (self.pixels, self.format)
        }

        pub(crate) fn into_rgba_pixels(self) -> Result<(Vec<u8>, u32, u32), PngDecodeError> {
            match self.format {
                ImageFormat::Rgb => {
                    expect_exact_pixel_len(&self.pixels, self.dimensions, 3)?;
                    let target_len = self.dimensions.byte_len(4)?;
                    PngDecodeBudget::inline_image().check_normalized_size(target_len)?;

                    let mut rgba = Vec::with_capacity(target_len);
                    for rgb in self.pixels.chunks_exact(3) {
                        rgba.extend_from_slice(&[rgb[0], rgb[1], rgb[2], 0xff]);
                    }

                    Ok((rgba, self.dimensions.width(), self.dimensions.height()))
                }
                ImageFormat::Rgba => {
                    expect_exact_pixel_len(&self.pixels, self.dimensions, 4)?;
                    Ok((
                        self.pixels,
                        self.dimensions.width(),
                        self.dimensions.height(),
                    ))
                }
            }
        }
    }

    pub(crate) fn decode_inline_png(data: &[u8]) -> Result<DecodedPng, PngDecodeError> {
        let budget = PngDecodeBudget::inline_image();
        let mut decoder = png::Decoder::new(Cursor::new(data));
        decoder.set_transformations(png::Transformations::normalize_to_color8());

        let mut reader = decoder
            .read_info()
            .map_err(|_| PngDecodeError::InvalidHeader)?;
        let header_dimensions = PngDimensions::new(reader.info().width, reader.info().height)?;

        // The header is trusted only enough to calculate a hard allocation ceiling.
        // Never call output_buffer_size() for dimensions that exceed the inline budget.
        budget.check_dimensions(header_dimensions)?;
        let output_buffer_size = reader.output_buffer_size();
        budget.check_output_buffer_size(output_buffer_size)?;

        let mut pixels = vec![0u8; output_buffer_size];
        let frame = reader
            .next_frame(&mut pixels)
            .map_err(|_| PngDecodeError::InvalidFrame)?;
        pixels.truncate(frame.buffer_size());

        let frame_dimensions = PngDimensions::new(frame.width, frame.height)?;
        budget.check_dimensions(frame_dimensions)?;
        normalize_color_layout(pixels, frame_dimensions, frame.color_type, budget)
    }

    fn normalize_color_layout(
        pixels: Vec<u8>,
        dimensions: PngDimensions,
        color_type: png::ColorType,
        budget: PngDecodeBudget,
    ) -> Result<DecodedPng, PngDecodeError> {
        match color_type {
            png::ColorType::Rgb => decoded_png(pixels, ImageFormat::Rgb, dimensions, 3, budget),
            png::ColorType::Rgba => decoded_png(pixels, ImageFormat::Rgba, dimensions, 4, budget),
            png::ColorType::Grayscale => expand_grayscale_to_rgb(pixels, dimensions, budget),
            png::ColorType::GrayscaleAlpha => {
                expand_grayscale_alpha_to_rgba(pixels, dimensions, budget)
            }
            png::ColorType::Indexed => Err(PngDecodeError::UnsupportedColorLayout),
        }
    }

    fn decoded_png(
        pixels: Vec<u8>,
        format: ImageFormat,
        dimensions: PngDimensions,
        bytes_per_pixel: usize,
        budget: PngDecodeBudget,
    ) -> Result<DecodedPng, PngDecodeError> {
        expect_exact_pixel_len(&pixels, dimensions, bytes_per_pixel)?;
        budget.check_normalized_size(pixels.len())?;
        Ok(DecodedPng {
            pixels,
            format,
            dimensions,
        })
    }

    fn expand_grayscale_to_rgb(
        pixels: Vec<u8>,
        dimensions: PngDimensions,
        budget: PngDecodeBudget,
    ) -> Result<DecodedPng, PngDecodeError> {
        expect_exact_pixel_len(&pixels, dimensions, 1)?;
        let target_len = dimensions.byte_len(3)?;
        budget.check_normalized_size(target_len)?;

        let mut rgb = Vec::with_capacity(target_len);
        for value in pixels {
            rgb.extend_from_slice(&[value, value, value]);
        }

        Ok(DecodedPng {
            pixels: rgb,
            format: ImageFormat::Rgb,
            dimensions,
        })
    }

    fn expand_grayscale_alpha_to_rgba(
        pixels: Vec<u8>,
        dimensions: PngDimensions,
        budget: PngDecodeBudget,
    ) -> Result<DecodedPng, PngDecodeError> {
        expect_exact_pixel_len(&pixels, dimensions, 2)?;
        let target_len = dimensions.byte_len(4)?;
        budget.check_normalized_size(target_len)?;

        let mut rgba = Vec::with_capacity(target_len);
        for gray_alpha in pixels.chunks_exact(2) {
            rgba.extend_from_slice(&[gray_alpha[0], gray_alpha[0], gray_alpha[0], gray_alpha[1]]);
        }

        Ok(DecodedPng {
            pixels: rgba,
            format: ImageFormat::Rgba,
            dimensions,
        })
    }

    fn expect_exact_pixel_len(
        pixels: &[u8],
        dimensions: PngDimensions,
        bytes_per_pixel: usize,
    ) -> Result<(), PngDecodeError> {
        let expected = dimensions.byte_len(bytes_per_pixel)?;
        if pixels.len() != expected {
            return Err(PngDecodeError::UnsupportedColorLayout);
        }
        Ok(())
    }
}
pub mod scroll;
pub mod sgr;
pub mod sixel;
pub mod tabs;
pub mod vte_handler;
