extends Node
## Autoload singleton: res://autoload/event_bus.gd -> "EventBus"
## Global signal hub so gameplay systems don't need direct references to
## each other (e.g. WeaponManager doesn't know Telemetry exists).

signal weapon_changed(weapon_name: String)
signal weapon_timer_changed(seconds_left: float, total: float)
signal enemy_defeated(enemy_name: String, position: Vector2)
signal boss_defeated()
signal boss_engaged(boss: Node)          # arena sealed, fight has started
signal boss_health_changed(current: float, max_hp: float)
signal boss_phase_changed(phase: int)    # 1, 2 or 3 -- drives the HUD callout
signal item_collected(item_name: String)
signal player_died(reason: String)
signal checkpoint_reached(respawn_position: Vector2)
signal player_respawned(respawn_position: Vector2)
signal shield_deflected(perfect: bool)
signal double_jumped()
