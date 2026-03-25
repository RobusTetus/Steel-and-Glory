extends Node

# Visual effects manager for combat feedback
# Creates particle effects and visual indicators


func create_hit_effect(pos: Vector3, color: Color = Color(1.0, 0.3, 0.3)) -> void:
	# Create a hit spark effect at the given position
	var particles := GPUParticles3D.new()
	var material := ParticleProcessMaterial.new()
	
	# Configure particle material
	material.direction = Vector3(0, 1, 0)
	material.spread = 45.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0
	material.gravity = Vector3(0, -10, 0)
	material.scale_min = 0.05
	material.scale_max = 0.15
	material.color = color
	
	# Configure particles
	particles.process_material = material
	particles.amount = 12
	particles.lifetime = 0.3
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.global_position = pos
	
	# Create a simple mesh for particles
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = color
	mesh_material.emission_enabled = true
	mesh_material.emission = color
	mesh_material.emission_energy_multiplier = 3.0
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh
	
	get_tree().current_scene.add_child(particles)
	particles.emitting = true
	
	# Clean up after particles finish
	get_tree().create_timer(0.5).timeout.connect(
		func() -> void:
			if is_instance_valid(particles):
				particles.queue_free()
	)


func create_blood_effect(pos: Vector3) -> void:
	create_hit_effect(pos, Color(0.6, 0.0, 0.0))


func create_parry_effect(pos: Vector3) -> void:
	# Create a golden parry spark effect
	var particles := GPUParticles3D.new()
	var material := ParticleProcessMaterial.new()
	
	material.direction = Vector3(0, 0.5, 0)
	material.spread = 180.0
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 10.0
	material.gravity = Vector3(0, -5, 0)
	material.scale_min = 0.03
	material.scale_max = 0.1
	material.color = Color(1.0, 0.85, 0.2)
	
	particles.process_material = material
	particles.amount = 24
	particles.lifetime = 0.4
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.global_position = pos
	
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = Color(1.0, 0.85, 0.2)
	mesh_material.emission_enabled = true
	mesh_material.emission = Color(1.0, 0.85, 0.2)
	mesh_material.emission_energy_multiplier = 5.0
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh
	
	get_tree().current_scene.add_child(particles)
	particles.emitting = true
	
	get_tree().create_timer(0.6).timeout.connect(
		func() -> void:
			if is_instance_valid(particles):
				particles.queue_free()
	)


func create_block_effect(pos: Vector3) -> void:
	# Create a blue block spark effect
	create_hit_effect(pos, Color(0.3, 0.6, 1.0))


func create_stagger_effect(pos: Vector3) -> void:
	# Create dizzy stars effect
	var particles := GPUParticles3D.new()
	var material := ParticleProcessMaterial.new()
	
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 1.0
	material.gravity = Vector3(0, 0, 0)
	material.scale_min = 0.08
	material.scale_max = 0.12
	material.color = Color(1.0, 1.0, 0.3)
	material.orbit_velocity_min = 2.0
	material.orbit_velocity_max = 3.0
	
	particles.process_material = material
	particles.amount = 5
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.global_position = pos + Vector3(0, 2.0, 0)
	
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = Color(1.0, 1.0, 0.3)
	mesh_material.emission_enabled = true
	mesh_material.emission = Color(1.0, 1.0, 0.3)
	mesh_material.emission_energy_multiplier = 2.0
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh
	
	get_tree().current_scene.add_child(particles)
	particles.emitting = true
	
	get_tree().create_timer(0.7).timeout.connect(
		func() -> void:
			if is_instance_valid(particles):
				particles.queue_free()
	)


func create_dodge_trail(start_pos: Vector3, end_pos: Vector3) -> void:
	# Create a brief trail effect for dodge
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	
	var direction := (end_pos - start_pos)
	var length := direction.length()
	mesh.size = Vector3(0.3, 0.3, length)
	
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.8, 1.0, 0.4)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = Color(0.5, 0.8, 1.0)
	material.emission_energy_multiplier = 1.5
	mesh.material = material
	
	mesh_instance.mesh = mesh
	mesh_instance.global_position = (start_pos + end_pos) / 2
	mesh_instance.look_at(end_pos)
	
	get_tree().current_scene.add_child(mesh_instance)
	
	# Fade out
	var tween := get_tree().create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(mesh_instance.queue_free)


func create_sword_trail(sword_node: Node3D, color: Color = Color(0.9, 0.9, 0.95)) -> void:
	# Create a brief sword trail effect
	if not is_instance_valid(sword_node):
		return
	
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 0.02, 0.8)
	
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, 0.6)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	mesh.material = material
	
	mesh_instance.mesh = mesh
	mesh_instance.global_transform = sword_node.global_transform
	
	get_tree().current_scene.add_child(mesh_instance)
	
	# Fade out quickly
	var tween := get_tree().create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.15)
	tween.tween_callback(mesh_instance.queue_free)


func create_death_effect(pos: Vector3) -> void:
	# Create death particles
	var particles := GPUParticles3D.new()
	var material := ParticleProcessMaterial.new()
	
	material.direction = Vector3(0, 1, 0)
	material.spread = 60.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 5.0
	material.gravity = Vector3(0, -8, 0)
	material.scale_min = 0.1
	material.scale_max = 0.25
	material.color = Color(0.5, 0.0, 0.0)
	
	particles.process_material = material
	particles.amount = 20
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 0.8
	particles.global_position = pos
	
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = Color(0.5, 0.0, 0.0)
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh
	
	get_tree().current_scene.add_child(particles)
	particles.emitting = true
	
	get_tree().create_timer(1.0).timeout.connect(
		func() -> void:
			if is_instance_valid(particles):
				particles.queue_free()
	)


func create_combo_effect(pos: Vector3, combo_count: int) -> void:
	# Create combo celebration effect
	var color: Color
	match combo_count:
		2: color = Color(0.8, 0.8, 0.2)
		3: color = Color(1.0, 0.6, 0.2)
		4: color = Color(1.0, 0.4, 0.2)
		_: color = Color(1.0, 0.2, 0.2)  # 5+
	
	var particles := GPUParticles3D.new()
	var material := ParticleProcessMaterial.new()
	
	material.direction = Vector3(0, 1, 0)
	material.spread = 30.0
	material.initial_velocity_min = 4.0
	material.initial_velocity_max = 8.0
	material.gravity = Vector3(0, -2, 0)
	material.scale_min = 0.05
	material.scale_max = 0.1
	material.color = color
	
	particles.process_material = material
	particles.amount = 8 + combo_count * 2
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.global_position = pos + Vector3(0, 1.5, 0)
	
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = color
	mesh_material.emission_enabled = true
	mesh_material.emission = color
	mesh_material.emission_energy_multiplier = 4.0
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh
	
	get_tree().current_scene.add_child(particles)
	particles.emitting = true
	
	get_tree().create_timer(0.7).timeout.connect(
		func() -> void:
			if is_instance_valid(particles):
				particles.queue_free()
	)
