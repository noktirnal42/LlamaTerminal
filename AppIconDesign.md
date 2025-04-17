# LlamaTerminal App Icon Design Specification

## Design Concept
The LlamaTerminal app icon should represent a modern AI-enhanced terminal while incorporating the llama theme. The design should be clean, professional, and recognizable at all sizes.

## Icon Design
1. **Base Design**: A sleek, minimalist terminal window with a stylized llama silhouette
2. **Color Scheme**: 
   - Primary background: Dark gradient (#1E1E2E to #181825)
   - Terminal frame: Medium gray (#313244)
   - Terminal text: Bright teal (#94E2D5)
   - Llama silhouette: Gradient from light purple (#CBA6F7) to light blue (#89B4FA)
   - Accent highlights: Soft pink (#F5C2E7)

3. **Layout**:
   - A modern, slightly rounded terminal window occupying approximately 80% of the icon space
   - Stylized llama head silhouette overlaid on the terminal or emerging from it
   - Command line symbols ($ or >) in the terminal area with pulsing cursor
   - Subtle code/text elements in the background

## Size-Specific Considerations
For smaller icons (16x16, 32x32):
- Simplify the design to just the terminal window with llama symbol
- Remove fine text details
- Increase contrast for better visibility

For larger icons (256x256 and above):
- Include more detail in the terminal window (syntax highlighted code)
- Add subtle texture to the llama silhouette
- Include subtle shadow/depth effects

## Icon Sizes and Locations
Create the following sizes and save them in the `LlamaTerminal/Assets.xcassets/AppIcon.appiconset/` directory:

| Size | Filename | Notes |
|------|----------|-------|
| 16x16 | app_icon_16.png | Simplest version, focus on shape recognition |
| 32x32 | app_icon_32.png | Slightly more detail than 16x16 |
| 64x64 | app_icon_64.png | Add basic terminal details |
| 128x128 | app_icon_128.png | Add more texture and command line symbols |
| 256x256 | app_icon_256.png | Full detail with code elements |
| 512x512 | app_icon_512.png | High-resolution version with all details |
| 1024x1024 | app_icon_1024.png | Master artwork with maximum detail |

## Icon Format
- Format: PNG with transparency
- Color profile: sRGB
- Bit depth: 24-bit color (8-bits per channel) + 8-bit alpha

## Visual Style Recommendations
1. Use a flat design with subtle depth cues rather than full 3D rendering
2. Ensure the icon remains recognizable when scaled down to 16x16
3. Create versions that work well on both light and dark backgrounds
4. Test the icon on different desktop backgrounds to ensure visibility

## Implementation Notes
After creating the icon files, place them in the `LlamaTerminal/Assets.xcassets/AppIcon.appiconset/` directory and ensure the `Contents.json` file is properly configured to reference these files.

