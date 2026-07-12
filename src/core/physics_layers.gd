class_name PhysicsLayers
extends RefCounted

const WORLD: int = 1 << 0
const PLAYER: int = 1 << 1
const ENTITIES: int = 1 << 2
const PICKUPS: int = 1 << 3

const PLAYER_BODY_MASK: int = WORLD | ENTITIES
const PLAYER_INTERACTION_MASK: int = WORLD | ENTITIES
const ENTITY_BODY_MASK: int = WORLD | PLAYER | ENTITIES
const PICKUP_BODY_MASK: int = PLAYER

const PLAYER_GROUP: StringName = &"player"
const CREATURE_GROUP: StringName = &"creatures"
const PICKUP_GROUP: StringName = &"pickups"
