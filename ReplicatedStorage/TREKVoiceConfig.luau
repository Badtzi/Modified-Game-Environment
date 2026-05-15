local VoiceConfig = {}

VoiceConfig.DefaultPackage = "USA"
VoiceConfig.FemaleMeshId = 48112070
VoiceConfig.SubtitleMaxDistance = 80
VoiceConfig.SubtitleStudsOffset = Vector3.new(0, 3, 0)
VoiceConfig.DefaultSubtitleDuration = 3.0

VoiceConfig.Reactions = {

	Reload = {
		Chance   = 1.0,
		Cooldown = 4.0,
	},

	Hit = {
		Chance   = 0.4,
		Cooldown = 3.0,
	},

	CauseDamage = {
		Chance   = 0.2,
		Cooldown = 5.0,
	},

	Kill = {
		Chance   = 0.8,
		Cooldown = 3.0,
	},

	VoicesOfTheDamned = {
		Chance   = 1.0,
		Cooldown = 0.0,
	},

	GrenadeNearby = {
		Chance   = 0.6,
		Cooldown = 5.0,
	},

	ThrowingGrenade = {
		Chance   = 0.8,
		Cooldown = 3.0,
	},

	EquipMelee = {
		Chance   = 0.5,
		Cooldown = 5.0,
	},

	Suppressed = {
		Chance   = 0.3,
		Cooldown = 6.0,
	},

	Burning = {
		Chance   = 1.0,
		Cooldown = 3.0,
	},

	BurnDeath = {
		Chance   = 1.0,
		Cooldown = 0.0,
	},

	BackpackIgnited = {
		Chance   = 1.0,
		Cooldown = 0.0,
	},

	Death = {
		Chance   = 1.0,
		Cooldown = 0.0,
	},
}

return VoiceConfig
