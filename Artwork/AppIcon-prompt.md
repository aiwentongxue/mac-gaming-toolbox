# Mac Game Toolbox icon

Generated with the built-in `image_gen` tool on 2026-10-31, with `transparent_background: true` for both calls.

## Initial generation prompt

Use case: logo-brand. Asset type: production macOS application icon for Mac Game Toolbox. Generate a brand-new polished 1024-square app icon. A single large white game controller centered on a vivid, bright cyan-to-azure blue rounded-square background. Clear bold controller silhouette with two rounded grips, dark blue plus-shaped D-pad on the left, four simple dark blue circular face buttons on the right, two small joystick circles, minimal restrained soft 3D depth and gentle shadows. Controller occupies about 72 percent of the icon width and is the dominant unmistakable shape, clearly readable at 16 and 32 pixel sizes. Background tile occupies about 90 percent of canvas with a standard macOS rounded-square silhouette, consistent safe padding all around and genuinely transparent outer corners. Fresh luminous blue and turquoise, white controller, high contrast, crisp balanced geometric design, modern premium Apple desktop application polish. Straight-on orthographic composition, no perspective tilt. No wrench, no tools, no metallic borders, no rings, no circular decoration, no glow loops, no text, no letters, no numbers, no brand marks, no watermark, no tiny textures or hardware details. Single icon only.

## Refinement prompt

Refine this macOS app icon for production. Preserve the bright cyan to blue background, the white controller, its composition, clean geometric D-pad, four face buttons, two joysticks, and subtle depth. Correct ONLY the outer edge quality and canvas padding: create a perfectly square 1024x1024 image with the rounded-square tile centered at 90 percent of canvas width and height. Outside the smooth rounded square must be fully transparent with ZERO stray blue or cyan pixels, no rough noise, no glow, no fringes, no detached flecks. Perfectly crisp smooth anti-aliased silhouette all the way around, balanced generous empty transparent margins on all four sides, sharp interior details. No wrench, no words, no letters, no border, no extra objects. This is a production app icon, not a mockup.

## Production assets

`AppIcon-generated.png` preserves the selected generated artwork. `AppIcon-master.png` is the 1024 px production master, with standard transparent padding and geometric clipping to remove stray outer pixels. Run `swift Scripts/export-app-icon.swift` from the repository to reproduce the master and all AppIcon slots. For the legacy image, the exporter only clips the tile and resamples it; that controller and background are ImageGen artwork. The production native icon uses the separately generated controller layer with a native opaque gradient.

## Native macOS 26+ icon

The production icon is now `Sources/MacGameToolbox/AppIcon.icon`. It separates the transparent game-controller foreground from an opaque native blue gradient. This avoids macOS 26 placing a legacy inset icon on an additional white/gray plate. Xcode compiles the icon stack for default, dark and monochrome appearances and generates the multi-size fallback for older macOS versions. The `LegacyAppIcon.appiconset` images and `AppIcon-master.png` are retained as source artwork; they are not the selected production app icon.

`Controller-generated.png` is the built-in ImageGen extraction used by `Scripts/export-app-icon.swift` to prepare the native foreground canvas. Exact extraction prompt:

Production app-icon foreground layer extraction. Use the supplied icon as the exact edit target. Remove ONLY the entire blue/cyan rounded-square background and all of its outer icon silhouette. Keep ONLY the white game controller, with its blue D-pad, four blue round buttons, and two blue joysticks. Preserve the controller design, orientation, proportions, white color, dark-blue controls, soft existing dimensional shading, and precise geometric outlines. The controller is the only object, centered on a square canvas, occupying approximately 78 percent of the canvas width. Everything outside the controller silhouette, including the gap under the controller between its grips, must be genuinely transparent. No background tile, no square, no border, no shadows extending beyond the controller, no new objects, no words, no letters. Clean smooth antialiased controller edges, no blue background remnants or detached flecks. This is a separate transparent foreground layer to be composed over a native full-bleed cyan-to-blue gradient in Apple's Icon Composer.
