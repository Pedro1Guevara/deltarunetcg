extends Control

signal avatar_changed(new_avatar_path)

@onready var current_preview: TextureRect = $BackgroundDimmer/PopupPanelContainer/VBoxContainer/CurrentAvatarPreview
@onready var avatars_grid: GridContainer = $BackgroundDimmer/PopupPanelContainer/VBoxContainer/ScrollContainer/GridContainer

const AVATAR_LIST = [
	"res://game/ui/Avatars/RedSoul.png",
	"res://game/ui/Avatars/OrangeSoul.png",
	"res://game/ui/Avatars/YellowSoul.png",
	"res://game/ui/Avatars/GreenSoul.png",
	"res://game/ui/Avatars/CyanSoul.png",
	"res://game/ui/Avatars/BlueSoul.png",
	"res://game/ui/Avatars/PurpleSoul.png",
	"res://game/ui/Avatars/MonsterSoul.png"
]

func _ready() -> void:
	update_preview(PlayerData.equipped_avatar)
	populate_avatar_grid()

func update_preview(path: String) -> void:
	if ResourceLoader.exists(path):
		current_preview.texture = load(path)

func populate_avatar_grid() -> void:
	for child in avatars_grid.get_children():
		child.queue_free()
		
	for path in AVATAR_LIST:
		var btn = TextureButton.new()
		btn.custom_minimum_size = Vector2(200, 200)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		
		if ResourceLoader.exists(path):
			btn.texture_normal = load(path)
			
		# Conecta o clique do botão
		btn.pressed.connect(Callable(self, "_on_avatar_selected").bind(path))
		avatars_grid.add_child(btn)

func _on_avatar_selected(path: String) -> void:
	update_preview(path)
	PlayerData.equipped_avatar = path
	PlayerData.save_game()
	emit_signal("avatar_changed", path)
	print("Avatar alterado para: ", path)


# Fecha apenas se clicar fora da área útil do painel central
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Pega no painel central onde estão os avatares
		var panel = $BackgroundDimmer/PopupPanelContainer
		
		# Se o clique estiver FORA dos limites globais do painel central, fecha o pop-up
		if not panel.get_global_rect().has_point(event.position):
			queue_free()
