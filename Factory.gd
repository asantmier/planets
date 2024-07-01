extends Building

var daylength := 5.0
var time := 0.0

# Called when the node enters the scene tree for the first time.
func _ready():
	time = 0.0


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	time += delta
	if time >= daylength:
		time -= daylength
		PlayerData.components += 5
