# Lumen Pro Camera

Native SwiftUI camera app for iPhone, built on AVFoundation.

## Included

- Live camera preview with grid overlay and lens zoom controls
- 0.5×, 1×, 2×, 3×, and 5× zoom stops (clamped to the active iPhone camera's available range)
- Manual shutter speed, ISO, focus, white balance, and exposure compensation
- JPEG, HEIF, and RAW + processed capture, with 12 MP / full-resolution options when the active iPhone camera supports them
- Macro, depth-matte portrait, flash Auto/On/Off, and capability-matched video resolution and frame-rate controls
- Photo, video, slow motion, Cinematic capture on compatible iOS 26+ hardware, time-lapse, and a four-frame Vision-aligned panorama mode
- A self-timer and 4:3, 3:2, or 16:9 processed-photo crops
- Optional date/time watermark on processed photos and stitched panoramas
- An original collection of color looks: Classic 35, True Color, Color Pop, Neutral, B&W, Leica-inspired, Hasselblad-inspired, Fujifilm-inspired, Natural, Vivid, Mono, Noir, Warm, Cool, Film, Golden, Faded, Teal, Portrait, Chrome, Dusk, Soft Portrait, and Street
- Flash control and saving captures to Photos

The available RAW formats, megapixel options, lenses, flash modes, video formats, and frame rates are read from the connected iPhone camera. RAW files are saved without the selected color look or aspect crop so they remain suitable for editing; the selected look and aspect crop are applied to the processed copy. Portrait capture preserves native depth and portrait matte data.

## Open

Open `LeicaManualCam.xcodeproj` in Xcode and run the `LeicaManualCam` scheme on an iPhone. Camera access is required; the simulator does not provide a real iPhone camera feed.
