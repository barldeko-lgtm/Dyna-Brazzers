class_name CreatureFaction
extends RefCounted

# Runtime ownership is intentionally separate from species data. The same
# dinosaur species may belong to the player, an enemy faction, aliens, or a
# neutral ecosystem without duplicating its biological resource.
const PLAYER: StringName = &"player"
const ENEMY: StringName = &"enemy"
const ALIEN: StringName = &"alien"
const NEUTRAL: StringName = &"neutral"
const META_KEY: StringName = &"dyna_faction_id"


static func normalize(faction_variant: Variant) -> StringName:
	if faction_variant == null:
		return PLAYER

	# Runtime faction values are already StringName in the normal path. Avoid
	# converting them to String and trimming them on every UI/energy/flag scan.
	if faction_variant is StringName:
		var faction_id: StringName = faction_variant
		return PLAYER if faction_id == StringName() else faction_id

	if faction_variant is String:
		var faction_text: String = faction_variant

		# Trimming is kept only for external/save compatibility paths.
		faction_text = faction_text.strip_edges()
		return PLAYER if faction_text.is_empty() else StringName(faction_text)

	var faction_text := String(faction_variant).strip_edges()
	return PLAYER if faction_text.is_empty() else StringName(faction_text)


static func get_id(entity: Node) -> StringName:
	if entity == null or not is_instance_valid(entity):
		return PLAYER

	# Player is the overwhelmingly common case. It is represented by the
	# absence of metadata, so this hot path performs no String allocations.
	if not entity.has_meta(META_KEY):
		return PLAYER

	var faction_variant: Variant = entity.get_meta(META_KEY)

	if faction_variant is StringName:
		var faction_id: StringName = faction_variant
		return PLAYER if faction_id == StringName() else faction_id

	return normalize(faction_variant)


static func set_id(entity: Node, faction_variant: Variant) -> StringName:
	var faction_id := normalize(faction_variant)

	if entity == null or not is_instance_valid(entity):
		return faction_id

	# Do not store the default player value on every creature and egg. Missing
	# metadata is already backward-compatible and means PLAYER everywhere.
	if faction_id == PLAYER:
		if entity.has_meta(META_KEY):
			entity.remove_meta(META_KEY)
	else:
		entity.set_meta(META_KEY, faction_id)

	return faction_id


static func is_player(entity: Node) -> bool:
	return get_id(entity) == PLAYER
