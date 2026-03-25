extends Node

# Audio manager singleton for playing game sounds
# Sounds are procedurally generated since we don't have audio files

# Sound pools for randomization
var _audio_players: Array[AudioStreamPlayer] = []
const POOL_SIZE := 8

func _ready() -> void:
	# Create a pool of audio players for concurrent sounds
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_audio_players.append(player)


func _get_available_player() -> AudioStreamPlayer:
	for player in _audio_players:
		if not player.playing:
			return player
	# If all are busy, return the first one (will interrupt it)
	return _audio_players[0]


# Play sword swing sound
func play_swing(is_heavy: bool = false) -> void:
	var player := _get_available_player()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.15 if not is_heavy else 0.25
	player.stream = gen
	player.volume_db = -8 if not is_heavy else -5
	player.pitch_scale = randf_range(0.9, 1.1)
	player.play()
	
	# Generate whoosh sound
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var frames := int(gen.mix_rate * gen.buffer_length)
	for i in range(frames):
		var t := float(i) / gen.mix_rate
		var envelope := sin(t * PI / gen.buffer_length)
		var noise := randf_range(-0.3, 0.3) * envelope
		var freq := 800.0 if not is_heavy else 400.0
		var whoosh := sin(t * freq * (1.0 - t * 2)) * envelope * 0.2
		playback.push_frame(Vector2(noise + whoosh, noise + whoosh))


# Play hit impact sound
func play_hit(is_critical: bool = false) -> void:
	var player := _get_available_player()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.2
	player.stream = gen
	player.volume_db = -3 if not is_critical else 0
	player.pitch_scale = randf_range(0.85, 1.15)
	player.play()
	
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var frames := int(gen.mix_rate * gen.buffer_length)
	for i in range(frames):
		var t := float(i) / gen.mix_rate
		var envelope := exp(-t * 20) * (1.0 - t / gen.buffer_length)
		var thud := sin(t * 150) * envelope * 0.5
		var crack := randf_range(-0.4, 0.4) * envelope * 0.6
		var impact := sin(t * 80) * exp(-t * 30) * 0.3
		var sample := thud + crack + impact
		playback.push_frame(Vector2(sample, sample))


# Play block/parry sound
func play_block(is_parry: bool = false) -> void:
	var player := _get_available_player()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.25 if is_parry else 0.15
	player.stream = gen
	player.volume_db = -5 if not is_parry else -2
	player.pitch_scale = randf_range(0.9, 1.2) if is_parry else randf_range(0.7, 0.9)
	player.play()
	
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var frames := int(gen.mix_rate * gen.buffer_length)
	for i in range(frames):
		var t := float(i) / gen.mix_rate
		var envelope := exp(-t * (15 if not is_parry else 8))
		var clang_freq := 2000 if is_parry else 800
		var clang := sin(t * clang_freq) * envelope * 0.4
		var ring := sin(t * (clang_freq * 1.5)) * exp(-t * 25) * 0.2
		var sample := clang + ring
		playback.push_frame(Vector2(sample, sample))


# Play kick sound
func play_kick() -> void:
	var player := _get_available_player()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.15
	player.stream = gen
	player.volume_db = -6
	player.pitch_scale = randf_range(0.9, 1.1)
	player.play()
	
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var frames := int(gen.mix_rate * gen.buffer_length)
	for i in range(frames):
		var t := float(i) / gen.mix_rate
		var envelope := exp(-t * 15)
		var thud := sin(t * 100) * envelope * 0.5
		var impact := randf_range(-0.2, 0.2) * exp(-t * 30) * 0.4
		playback.push_frame(Vector2(thud + impact, thud + impact))


# Play death sound
func play_death() -> void:
	var player := _get_available_player()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.5
	player.stream = gen
	player.volume_db = -4
	player.pitch_scale = randf_range(0.8, 1.0)
	player.play()
	
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var frames := int(gen.mix_rate * gen.buffer_length)
	for i in range(frames):
		var t := float(i) / gen.mix_rate
		var envelope := (1.0 - t / gen.buffer_length)
		var groan := sin(t * 180 * (1.0 - t * 0.5)) * envelope * 0.3
		var thud := sin(t * 60) * exp(-t * 8) * 0.4
		playback.push_frame(Vector2(groan + thud, groan + thud))


# Play footstep sound
func play_footstep(is_sprint: bool = false) -> void:
	var player := _get_available_player()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.08
	player.stream = gen
	player.volume_db = -15 if not is_sprint else -12
	player.pitch_scale = randf_range(0.8, 1.2)
	player.play()
	
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var frames := int(gen.mix_rate * gen.buffer_length)
	for i in range(frames):
		var t := float(i) / gen.mix_rate
		var envelope := exp(-t * 40)
		var step := randf_range(-0.3, 0.3) * envelope
		var thud := sin(t * 80) * exp(-t * 50) * 0.2
		playback.push_frame(Vector2(step + thud, step + thud))


# Play dodge/roll sound
func play_dodge() -> void:
	var player := _get_available_player()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.2
	player.stream = gen
	player.volume_db = -8
	player.pitch_scale = randf_range(0.9, 1.1)
	player.play()
	
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var frames := int(gen.mix_rate * gen.buffer_length)
	for i in range(frames):
		var t := float(i) / gen.mix_rate
		var envelope := sin(t * PI / gen.buffer_length)
		var whoosh := randf_range(-0.2, 0.2) * envelope
		var rustle := sin(t * 300 * (1.0 + randf() * 0.1)) * envelope * 0.1
		playback.push_frame(Vector2(whoosh + rustle, whoosh + rustle))


# Play stagger sound
func play_stagger() -> void:
	var player := _get_available_player()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.25
	player.stream = gen
	player.volume_db = -6
	player.pitch_scale = randf_range(0.7, 0.9)
	player.play()
	
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var frames := int(gen.mix_rate * gen.buffer_length)
	for i in range(frames):
		var t := float(i) / gen.mix_rate
		var envelope := exp(-t * 8)
		var grunt := sin(t * 120 * (1.0 - t * 0.3)) * envelope * 0.3
		var stumble := randf_range(-0.2, 0.2) * envelope * 0.2
		playback.push_frame(Vector2(grunt + stumble, grunt + stumble))


# Play combo sound
func play_combo(combo_count: int) -> void:
	var player := _get_available_player()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 22050
	gen.buffer_length = 0.15
	player.stream = gen
	player.volume_db = -8
	player.pitch_scale = 1.0 + (combo_count * 0.1)  # Higher pitch for higher combos
	player.play()
	
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var frames := int(gen.mix_rate * gen.buffer_length)
	var base_freq := 600 + (combo_count * 100)
	for i in range(frames):
		var t := float(i) / gen.mix_rate
		var envelope := exp(-t * 15)
		var note := sin(t * base_freq) * envelope * 0.3
		var harmonic := sin(t * base_freq * 1.5) * envelope * 0.15
		playback.push_frame(Vector2(note + harmonic, note + harmonic))
