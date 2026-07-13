# Equipment System Architecture

## Product goal

Build Minecraft/RPG style equipment foundation without coupling Player, UI and combat.

## Domain ownership

```
EquipmentService
├── Equipment slots
├── Attribute aggregation
├── Save/restore contract
└── Equipment events
```

## Design rules

- Player only requests actions.
- UI only renders snapshots.
- Combat reads final attributes.
- Inventory owns item quantity.
- Equipment owns equipped state.

## Future extensions

- Armor sets.
- Enchantments.
- Rarity.
- Durability integration.
- Passive skills.
- Cosmetic skins.

## Acceptance

Every extension must provide:

1. Data registry.
2. Domain service.
3. Save compatibility.
4. Automated tests.
5. Desktop verification.
6. Release smoke verification.
