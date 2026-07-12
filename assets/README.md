# Procedural asset policy

Star World v1.0 builds its low-poly voxel creatures, item pickup cubes, UI panels, and sound effects at runtime. This keeps the project redistributable without third-party art or audio licenses.

- Creature models are assembled from `BoxMesh` parts in `src/entity/`.
- Item colors come from `data/items.json`.
- Environment, block-break, block-place, pickup, crafting, and creature sounds are synthesized as PCM streams by `src/audio/audio_service.gd`.

Replacing these procedural assets does not change gameplay contracts: keep item/species IDs and the public audio method names stable.
