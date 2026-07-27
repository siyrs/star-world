# Procedural asset policy

Star World v1.0 builds its low-poly voxel creatures, item pickup cubes, UI panels, UI bevel/slot/dirt textures, and sound effects at runtime. This keeps the project redistributable without third-party art or audio licenses.

- Creature models are assembled from `BoxMesh` parts in `src/entity/`.
- Item colors come from `data/items.json`.
- Environment, block-break, block-place, pickup, crafting, creature, footstep, digging, eating, reward, and landing sounds are synthesized as PCM streams by `src/audio/audio_service.gd`.
- UI textures (buttons, panels, slots, menu dirt background, hurt vignette) are generated at runtime by `src/ui/pixel_ui_textures.gd`.

Replacing these procedural assets does not change gameplay contracts: keep item/species IDs and the public audio method names stable.

## Bundled font (single documented exception)

`assets/fonts/fusion_pixel_12px_mono.ttf` is the **Fusion Pixel Font 12px (monospaced)**, an open-source Pan-CJK pixel typeface by TakWolf and contributors, licensed under the **SIL Open Font License 1.1** (see `assets/fonts/OFL.txt`). OFL permits bundling, embedding, and redistribution with the game, including commercial use; the font itself may not be sold on its own. It was chosen because it covers Simplified Chinese, Traditional Chinese, Japanese, Korean, and Latin at 8/10/12px sizes, matching the game's pixel-art identity.

- Upstream: https://github.com/TakWolf/fusion-pixel-font
- If the file is absent, the game falls back to the engine default font and logs one warning.
