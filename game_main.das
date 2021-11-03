require daslib/media

struct Car
	position: float2
	direction: float2
	target: float2
	lane: int
	stopped: bool
	
	color: float3
	
	on_road: int
	on_junction: int
	next_road: int
	next_junction: int

struct Junction
	center: float2
	roads: int[4]

struct Road
	p1, p2: float2
	junction1, junction2: int
	
struct Camera
	center: float2
	screen_size: float2
	zoom: float
	zoom_target: float
	
struct Rect
	left, right: float
	top, bottom: float
	
struct Building
	rect: Rect
	color: float3
	height: float

let 
	junction_width = 50.0
	road_length = 200.0
	sidewalk_width = 10.0
	lane_width = 0.25 * junction_width
	road_color = make_color(0.5)
	sidewalk_color = make_color(0.4)
	car_color = make_color(1.0, 1.0, 0.0)
	car_length = 10.0
	car_width = 6.0
	car_speed = 100.0
	car_mass = 100.0
	
	other_car_speed = 20.0
	
	junction_row_n = 3
	junction_col_n = 3
	
	target_color = float3(1.0, 1.0, 0.0)
	target_color_id = make_color(target_color)

	pedestrian_radius = 1.0
	pedestrian_color = float3(0.0, 0.0, 1.0)
	pedestrian_color_id = make_color(pedestrian_color)
	pedestrian_n = 20
	pedestrian_pick_up_radius = 20.0
	stop_speed_cap = 5.0
	
var
	car_position: float2
	car_velocity: float2
	car_angle: float
	car_angular_velocity: float
	car_inertia: float
	
	camera: Camera
	pedestrian_positions: array<float2>
	highlighted_pedestrian_id = -1
	pedestrian_picked_up = false
	target_position: float2
	
	roads: array<Road>
	junctions: array<Junction>
	cars: array<Car>
	buildings: array<Building>
		
	semaphore_time = 0.0
	semaphore_index = 0
	
	tutorial_index = 0
	tutorial_switch_time = 0.0
	tutorial_highlight_time = 0.0
	tutorial_lerp_ratio = 0.0
	
	score = 0
	current_score = 100
	speed_bonus = 0.0
	
	no_collision_frame_count = 0
	collision_penalty = 0
	collision_penalty_time = 0.0
	
	time_remaining = 0.0

	seed: int4

def connect_road_junction1(road_id, junction_id: int)
	roads[road_id].junction1 = junction_id
	for i in range(4)
		if junctions[junction_id].roads[i] == -1
			junctions[junction_id].roads[i] = road_id
			return
			
def connect_road_junction2(road_id, junction_id: int)
	roads[road_id].junction2 = junction_id
	for i in range(4)
		if junctions[junction_id].roads[i] == -1
			junctions[junction_id].roads[i] = road_id
			return
	
def turn_to_right(v: float2): float2
	var result = float2(v.y, -v.x)
	return result
	
def turn_to_left(v: float2): float2
	var result = float2(-v.y, v.x)
	return result
	
def get_junction_enter_position(junction_id, road_id: int; lane: int): float2
	var road = roads[road_id]
	if road.junction1 == junction_id
		var side_dir = normalize(turn_to_right(road.p1 - road.p2))
		return road.p1 - (float(lane) + 0.5) * lane_width * side_dir
	else
		var side_dir = normalize(turn_to_right(road.p2 - road.p1))
		return road.p2 - (float(lane) + 0.5) * lane_width * side_dir
		
def get_junction_enter_direction(junction_id, road_id): float2
	var road = roads[road_id]
	if road.junction1 == junction_id
		return normalize(road.p1 - road.p2)
	else
		return normalize(road.p2 - road.p1)
		
def get_junction_leave_position(junction_id, road_id: int; lane: int)
	var road = roads[road_id]
	if road.junction1 == junction_id
		var side_dir = normalize(turn_to_right(road.p1 - road.p2))
		return road.p1 + (float(lane) + 0.5) * lane_width * side_dir
	else
		var side_dir = normalize(turn_to_right(road.p2 - road.p1))
		return road.p2 + (float(lane) + 0.5) * lane_width * side_dir
	
def generate_buildings(rect: Rect)
	let max_side = 150.0
	let min_side  = 50.0
	let space = 10.0

	var width = rect.right - rect.left
	var height = rect.bottom - rect.top
	
	var too_wide = (width > max_side)
	var too_high = (height > max_side)
	
	var split_width = false
	var split_height = false
	
	if too_wide && too_high
		split_width = ((random_int(seed) % 2) == 0)
		split_height = !split_width
	elif too_wide
		split_width = true
	elif too_high
		split_height = true
	
	if split_width
		var min_split = min_side + space
		var max_split = width - min_side - space
		var split = rect.left + lerp(min_split, max_split, random_float(seed))
		
		var left_rect = rect
		left_rect.right = split - 0.5 * space
		generate_buildings(left_rect)
		
		var right_rect = rect
		right_rect.left = split + 0.5 * space
		generate_buildings(right_rect)
	elif split_height
		var min_split = min_side + space
		var max_split = height - min_side - space
		var split = rect.top + lerp(min_split, max_split, random_float(seed))
		
		var top_rect = rect
		top_rect.bottom = split - 0.5 * space
		generate_buildings(top_rect)
	
		var bottom_rect = rect
		bottom_rect.top = split + 0.5 * space
		generate_buildings(bottom_rect)
	else
		var building: Building
		building.rect = rect
		// building.color = 0.2 * float3(random_float(seed), random_float(seed), random_float(seed))
		building.color = (0.5 + 0.5 * random_float(seed)) * float3(0.4, 0.2, 0.2)
		building.height = 0.5 * 5.0 * random_float(seed)
		
		push(buildings, building)
	
	return
	
[export]
def initialize
	set_resolution(1024, 768)
    set_window_title("Game")
	car_position = float2(0, 0)
	car_angle = 1.0
	
	score = 0
	
	tutorial_index = 0
	tutorial_switch_time = 0.0
	
	time_remaining = float(3 * 60)
	
	clear(pedestrian_positions)
	for i in range(pedestrian_n)
		var position = get_random_sidewalk_position(seed)
		push(pedestrian_positions, position)
		
	var car_radius = sqrt(sqr(0.5 * car_width) + sqr(0.5 * car_length))
	car_inertia = car_mass * sqr(car_radius)
		
	pedestrian_picked_up = false
	
	camera.zoom = 1.0
	
	clear(junctions)
	clear(roads)
	
	for col in range(junction_col_n)
		for row in range(junction_row_n)
			var junction: Junction
			for i in range(4)
				junction.roads[i] = -1
			junction.center.x = float(row) * (junction_width + road_length) + 0.5 * junction_width
			junction.center.y = float(col) * (junction_width + road_length) + 0.5 * junction_width
			push(junctions, junction)
			
	for row in range(junction_row_n)
		for col in range(junction_col_n - 1)
			var y = float(row) * (junction_width + road_length) + 0.5 * junction_width
			var left = junction_width + float(col) * (junction_width + road_length)
			var right = left + road_length
			
			var left_junction_id = junction_col_n * row + col
			var right_junction_id = junction_col_n * row + (col + 1)
			
			var road: Road
			road.p1 = float2(left, y)
			road.p2 = float2(right, y)
			
			push(roads, road)
			var road_id = length(roads) - 1
			
			connect_road_junction1(road_id, left_junction_id)
			connect_road_junction2(road_id, right_junction_id)
			
	for col in range(junction_col_n)
		for row in range(junction_row_n - 1)
			var x = float(col) * (junction_width + road_length) + 0.5 * junction_width
			var top = junction_width + float(row) * (junction_width + road_length)
			var bottom = top + road_length
			
			var top_junction_id = row * junction_col_n + col
			var bottom_junction_id = (row + 1) * junction_col_n + col
			
			var road: Road
			road.p1 = float2(x, top)
			road.p2 = float2(x, bottom)
			
			push(roads, road)
			var road_id = length(roads) - 1
			
			connect_road_junction1(road_id, top_junction_id)
			connect_road_junction2(road_id, bottom_junction_id)
			
	clear(cars)
	for road_id in range(length(roads))
		var road = roads[road_id]
		var dir = normalize(road.p2 - road.p1)
		var side_dir = float2(dir.y, -dir.x)
		
		for lane in range(2)
			var car: Car;
			car.lane = lane
			var ratio = random_float(seed)
			var start_pos = lerp(road.p1, road.p2, ratio)
			start_pos -= (0.5 + float(car.lane)) * lane_width * side_dir
			car.position = start_pos
			car.direction = dir
			car.target = get_junction_enter_position(road.junction2, road_id, car.lane)
			car.on_road = road_id
			car.on_junction = -1
			car.next_junction = road.junction2
			car.next_road = -1
			car.color = float3(random_float(seed), random_float(seed), random_float(seed))
			push(cars, car)
			
			ratio = random_float(seed)
			start_pos = lerp(road.p1, road.p2, ratio)
			start_pos += (0.5 + float(car.lane)) * lane_width * side_dir
			car.position = start_pos
			car.target = get_junction_enter_position(road.junction1, road_id, car.lane)
			car.on_road = road_id
			car.on_junction = -1
			car.next_junction = road.junction1
			car.next_road = -1
			car.color = float3(random_float(seed), random_float(seed), random_float(seed))
			push(cars, car)
			
	
	var map_width = float(junction_col_n) * junction_width + float(junction_col_n - 1) * road_length
	var map_height = float(junction_row_n) * junction_width + float(junction_row_n - 1) * road_length
	
	clear(buildings)
	var rect: Rect
	
	// north
	rect.left = -sidewalk_width
	rect.right = map_width + sidewalk_width
	rect.bottom = -sidewalk_width
	rect.top = rect.bottom - junction_width
	generate_buildings(rect)
	
	// south
	rect.left = -sidewalk_width
	rect.right = map_width + sidewalk_width
	rect.top = map_height + sidewalk_width
	rect.bottom = rect.top + junction_width
	generate_buildings(rect)
	
	// west
	rect.top = -sidewalk_width
	rect.bottom = map_height + sidewalk_width
	rect.right = -sidewalk_width
	rect.left = rect.right - junction_width
	generate_buildings(rect)
	
	// east
	rect.top = -sidewalk_width
	rect.bottom = map_height + sidewalk_width
	rect.left = map_width + sidewalk_width
	rect.right = rect.left + junction_width
	generate_buildings(rect)
			
	for row in range(junction_row_n - 1)
		var top = float(row) * (junction_width + road_length) + junction_width + sidewalk_width
		for col in range(junction_col_n - 1)
			var left = float(col) * (junction_width + road_length) + junction_width + sidewalk_width
			rect.left = left
			rect.right = left + road_length - 2.0 * sidewalk_width
			rect.top = top
			rect.bottom = top + road_length - 2.0 * sidewalk_width
			generate_buildings(rect)
			
    return
	
def transform(camera: Camera; pos: float2)
	var pos2 = pos
	pos2 -= camera.center
	pos2 *= camera.zoom
	pos2 += 0.5 * camera.screen_size
	return pos2;
	
def transform_at_z(camera: Camera; pos: float2; z: float)
	var pos2 = pos
	pos2 -= camera.center
	pos2 *= camera.zoom + z
	pos2 += 0.5 * camera.screen_size
	return pos2
	
def transform_length(camera: Camera; length: float): float
	var result = camera.zoom * length
	return result
	
def draw_rect_outline(camera: Camera; rect: Rect; color: uint)
	var top_left = transform(camera, float2(rect.left, rect.top))
	var bottom_right = transform(camera, float2(rect.right, rect.bottom))
	line(top_left.x, top_left.y, top_left.x, bottom_right.y, color)
	line(bottom_right.x, top_left.y, bottom_right.x, bottom_right.y, color)
	line(top_left.x, top_left.y, bottom_right.x, top_left.y, color)
	line(top_left.x, bottom_right.y, bottom_right.x, bottom_right.y, color)
	
def draw_rect(camera: Camera; left, top, width, height: float; color: uint)
	var top_left = transform(camera, float2(left, top))
	var bottom_right = transform(camera, float2(left + width, top + height))
	var size = bottom_right - top_left;
	fill_rect(top_left.x, top_left.y, size.x, size.y, color)
	
def draw_rect(camera: Camera; rect: Rect; color: uint)
	draw_rect(camera, rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top, color)
	
def draw_rect_center_radius(camera: Camera; position: float2; radius: float; color: uint)
	var left = position.x - radius
	var top = position.y - radius
	var size = 2.0 * radius
	draw_rect(camera, left, top, size, size, color)
	
def draw_rect_3d(camera: Camera; rect: Rect; z: float; color: float3)
	var top_left = float2(rect.left, rect.top)
	var bottom_right = float2(rect.right, rect.bottom)
	
	var top_left0 = transform(camera, top_left)
	var bottom_right0 = transform(camera, bottom_right)
	var top_right0 = float2(bottom_right0.x, top_left0.y)
	var bottom_left0 = float2(top_left0.x, bottom_right0.y)
	
	var top_left1 = transform_at_z(camera, top_left, z)
	var bottom_right1 = transform_at_z(camera, bottom_right, z)
	var top_right1 = float2(bottom_right1.x, top_left1.y)
	var bottom_left1 = float2(top_left1.x, bottom_right1.y)
	
	var color_code = make_color(color)
	fill_rect(top_left1.x, top_left1.y, bottom_right1.x - top_left1.x, bottom_right1.y - top_left1.y, color_code)
	
	var side_color_code = make_color(0.8 * color)
	var points: float2[4]
	
	// top side
	if top_left0.y > 0.5 * camera.screen_size.y
		points[0] = top_left0
		points[1] = top_right0
		points[2] = top_right1
		points[3] = top_left1
		fill_convex_polygon(points, side_color_code)
	
	// bottom side
	if bottom_right0.y < 0.5 * camera.screen_size.y
		points[0] = bottom_right0
		points[1] = bottom_left0
		points[2] = bottom_left1
		points[3] = bottom_right1
		fill_convex_polygon(points, side_color_code)
		
	// left side
	if top_left0.x > 0.5 * camera.screen_size.x
		points[0] = bottom_left0
		points[1] = top_left0
		points[2] = top_left1
		points[3] = bottom_left1
		fill_convex_polygon(points, side_color_code)
		
	// right side
	if bottom_right0.x < 0.5 * camera.screen_size.x
		points[0] = top_right0
		points[1] = bottom_right0
		points[2] = bottom_right1
		points[3] = top_right1
		fill_convex_polygon(points, side_color_code)
	
def draw_circle(camera: Camera; center: float2; radius: float; color: uint)
	var center_transformed = transform(camera, center)
	var screen_radius = transform_length(camera, radius)
	circle(center_transformed.x, center_transformed.y, screen_radius, color)
	
def draw_line(camera: Camera; p1, p2: float2; color: uint)
	var tp1 = transform(camera, p1)
	var tp2 = transform(camera, p2)
	line(tp1.x, tp1.y, tp2.x, tp2.y, color)
	
def draw_line_xy(camera: Camera; x1, y1, x2, y2: float; color: uint)
	var p1 = float2(x1, y1)
	var p2 = float2(x2, y2)
	draw_line(camera, p1, p2, color)
	
def rect_two_corners(p1, p2: float2): Rect
	var rect: Rect
	rect.left = min(p1.x, p2.x)
	rect.right = max(p1.x, p2.x)
	rect.top = min(p1.y, p2.y)
	rect.bottom = max(p1.y, p2.y)
	return rect
	
def rect_contains_position(rect: Rect; position: float2)
	var x = (rect.left <= position.x && position.x <= rect.right)
	var y = (rect.top <= position.y && position.y <= rect.bottom)
	return x && y

def get_distance_square(p1, p2: float2): float
	var result = (p1.x - p2.x) * (p1.x - p2.x) + (p1.y - p2.y) * (p1.y - p2.y)
	return result
	
def unproject(camera: Camera; p2: float2): float2
	var p = p2
	p -= 0.5 * camera.screen_size
	p *= (1.0 / camera.zoom)
	p += camera.center
	return p
	
def unproject_xy(camera: Camera; x, y: float): float2
	var p2 = float2(x, y)
	var p = unproject(camera, p2)
	return p
	
def get_visible_rect(camera: Camera): Rect
	var top_left = unproject_xy(camera, 0.0, 0.0)
	var bottom_right = unproject_xy(camera, camera.screen_size.x, camera.screen_size.y)
	
	var rect = rect_two_corners(top_left, bottom_right)
	return rect
	
def get_length(v: float2): float
	var length = sqrt(sqr(v.x) + sqr(v.y))
	return length

def get_distance(p1, p2: float2): float
	return get_length(p2 - p1)
	
def get_junction_random_road_connection_except(junction_id, road_id: int): int
	var road_ids:array<int>
	var junction = junctions[junction_id]
	for i in range(4)
		if junction.roads[i] != -1 && junction.roads[i] != road_id
			push(road_ids, junction.roads[i])
			
	var index = random_int(seed) % length(road_ids)
	return road_ids[index]
	
def get_road_other_junction_connection(road_id, junction_id: int)
	var road = roads[road_id]
	if road.junction1 == junction_id
		return road.junction2
	else
		return road.junction1
	
def get_direction_vector(angle: float): float2
	return float2(cos(angle), sin(angle))	
	
def get_building_center(building: Building): float2
	var rect = building.rect
	return 0.5 * float2(rect.left + rect.right, rect.top + rect.bottom)
	
def get_car_obb(car: Car)
	var box: OBB
	box.center = car.position
	box.direction = car.direction
	box.width = car_width
	box.length = car_length
	return box

[export]
def act(dt: float)

    if get_key(VK_ESCAPE)
        schedule_quit_game()
		
	if get_key(VK_RETURN)
		initialize()
		
	time_remaining = max(0.0, time_remaining - dt)
	if time_remaining == 0.0
		return
		
	semaphore_time += dt
	if semaphore_time > 5.0
		semaphore_time = 0.0
		semaphore_index++
		if semaphore_index >= 12
			semaphore_index -= 12
	
	var car_direction = float2(cos(car_angle), sin(car_angle))
	var car_side_direction = float2(car_direction.y, -car_direction.x)
	
	let pull_strength = 5000.0
	
	var speed = get_length(car_velocity)
	
	var max_zoom_diff = 10.0 * dt
	
	camera.zoom_target = 10.0 / (1.0 + 0.02 * speed)
	if camera.zoom < camera.zoom_target
		camera.zoom = min(camera.zoom + max_zoom_diff, camera.zoom_target)
	elif camera.zoom > camera.zoom_target
		camera.zoom = max(camera.zoom - max_zoom_diff, camera.zoom_target)
	
	var friction = (1.0 / dt) * -0.9 * car_velocity
	var force = friction
	
	car_angular_velocity = 0.0
	
	var drive = false
	
	if get_key(VK_UP) || get_key(VK_W)
		force += pull_strength * car_direction
		drive = true
	if get_key(VK_DOWN) || get_key(VK_S)
		force -= pull_strength * car_direction
		drive = true
	if get_key(VK_LEFT) || get_key(VK_A)
		car_angular_velocity = -1.0 * (1.0 + speed / 100.0)
		drive = true
	if get_key(VK_RIGHT) || get_key(VK_D)
		car_angular_velocity = +1.0 * (1.0 + speed / 100.0)
		drive = true
		
	if drive && tutorial_index == 0 && tutorial_switch_time == 0.0
		tutorial_switch_time = 1.0
		
	if speed < 10.0
		car_angular_velocity = 0.0
	if speed > 30.0
		car_angular_velocity *= 0.8
	if speed > 50.0
		car_angular_velocity *= 0.8
		
	var going_backwards = (dot(car_direction, car_velocity) < 0.0)
	if going_backwards
		car_angular_velocity = -car_angular_velocity
		
	var acceleration = (1.0 / car_mass) * force
	car_velocity += dt * acceleration
	
	var side_velocity = dot(car_velocity, car_side_direction) * car_side_direction
	car_velocity -= 0.9 * side_velocity
	
	var box: OBB
	box.center = car_position
	box.direction = get_direction_vector(car_angle)
	box.width = car_width
	box.length = car_length
	
	var collided = false
	
	for car in cars
		var box2 = get_car_obb(car)
		if obbs_collide(box, box2)
			var collision = get_obb_collision(box, box2)
			var velocity2 = other_car_speed * car.direction
			if car.stopped
				velocity2 = float2(0, 0)
			apply_collision(collision, velocity2)
			collided = true
			
	for building in buildings
		var box2: OBB
		var rect = building.rect
		box2.center = 0.5 * float2(rect.left + rect.right, rect.top + rect.bottom)
		box2.direction = float2(0, 1)
		box2.width = rect.right - rect.left
		box2.length = rect.bottom - rect.top
		if obbs_collide(box, box2)
			var collision = get_obb_collision(box, box2)
			var velocity2 = float2(0, 0)
			apply_collision(collision, velocity2)
			collided = true
			
	if collided
		if speed > 30.0 && no_collision_frame_count >= 10
			collision_penalty = int(speed)
			current_score = max(0, current_score - collision_penalty)
			collision_penalty_time = 1.0
		no_collision_frame_count = 0
	else
		no_collision_frame_count++
		
	collision_penalty_time = max(0.0, collision_penalty_time - dt)
	
	car_position += dt * car_velocity
	car_angle += dt * car_angular_velocity
		
	camera.center = car_position
	camera.screen_size.x = float(get_screen_width())
	camera.screen_size.y = float(get_screen_height())
	
	highlighted_pedestrian_id = -1
	if !pedestrian_picked_up
		for i in range(pedestrian_n)
			var distance_square = get_distance_square(car_position, pedestrian_positions[i])
			if distance_square < pedestrian_pick_up_radius * pedestrian_pick_up_radius
				highlighted_pedestrian_id = i
				break;

	if highlighted_pedestrian_id != -1
		if tutorial_index == 1 && tutorial_switch_time == 0.0
			tutorial_index++
	
		if speed < stop_speed_cap
			pedestrian_picked_up = true
			pedestrian_positions[highlighted_pedestrian_id] = get_random_sidewalk_position(seed)
			highlighted_pedestrian_id = -1
			while true
				target_position = get_random_sidewalk_position(seed)
				var distance = get_distance(target_position, car_position)
				if distance > 1.5 * road_length
					current_score = int(distance)
					break
					

	if pedestrian_picked_up
		if tutorial_index == 2 && tutorial_switch_time == 0.0
			tutorial_index++
	
		var distance_square = get_distance_square(car_position, target_position)
		if speed < stop_speed_cap && distance_square < pedestrian_pick_up_radius * pedestrian_pick_up_radius
			pedestrian_picked_up = false
			score += current_score

			if tutorial_index == 4
				tutorial_index++
				tutorial_switch_time = 5.0

	let car_movement = dt * other_car_speed
	
	for i in range(1, length(buildings))
		var dist_sq_i = get_distance_square(car_position, get_building_center(buildings[i]))
		var j = i - 1
		var building_i = buildings[i]
		while true
			if j < 0
				break
			
			var dist_sq_j = get_distance_square(car_position, get_building_center(buildings[j]))
			if dist_sq_j > dist_sq_i
				break
		
			buildings[j + 1] = buildings[j]
			j = j -1
			
		buildings[j + 1] = building_i

	for car in cars
		car.direction = normalize(car.target - car.position)
		var target_distance = get_distance(car.position, car.target)
		
		var stop = false
		if car.on_road != -1 && target_distance < 5.0
			if semaphore_is_red(car.on_road, car.next_junction, semaphore_index)
				stop = true
				
		var front = car.position + 0.75 * car_length * car.direction
		
		if obb_contains_position(box, front)
			stop = true
		
		for car1 in cars
			if car1.on_road == car.on_road && car1.on_junction == car.on_junction
				if car1.next_road == car.next_road && car1.next_junction == car.next_junction
					var box1 = get_car_obb(car1)
					if obb_contains_position(box1, front)
						stop = true
						break
				
		car.stopped = stop
			
		if stop
			continue
		
		if target_distance > car_movement
			car.position += car_movement * car.direction
		else
			if car.on_road != -1
				car.on_junction = car.next_junction
				car.next_junction = -1
				car.next_road = get_junction_random_road_connection_except(car.on_junction, car.on_road)
				car.on_road = -1
				car.lane = random_int(seed) % 2
				car.target = get_junction_leave_position(car.on_junction, car.next_road, car.lane)
			else
				car.on_road = car.next_road;
				car.next_road = -1
				car.next_junction = get_road_other_junction_connection(car.on_road, car.on_junction)
				car.on_junction = -1
				car.target = get_junction_enter_position(car.next_junction, car.on_road, car.lane)	
				
	if pedestrian_picked_up
		if speed > 50.0
			speed_bonus += 10.0 * dt
		else
			current_score += int(speed_bonus)
			speed_bonus = 0.0
				
	if tutorial_switch_time > 0.0
		tutorial_switch_time = max(tutorial_switch_time - dt, 0.0)
		if tutorial_switch_time == 0.0
			tutorial_index++

	tutorial_highlight_time += dt
	tutorial_highlight_time -= floor(tutorial_highlight_time)
	
	if tutorial_highlight_time < 0.5
		tutorial_lerp_ratio = 2.0 * tutorial_highlight_time
	else
		tutorial_lerp_ratio = 2.0 - 2.0 * tutorial_highlight_time
				
    return
	
def turns_to_right(p1, p2, p3: float2)
	var dx1 = p2.x - p1.x
	var dy1 = p2.y - p1.y
	var dx2 = p3.x - p2.x
	var dy2 = p3.y - p2.y
	
	var det = (dx1 * dy2) - (dx2 * dy1)
	return (det > 0.0)
	
def draw_car_3d(camera: Camera; center: float2; direction: float2; color: float3)
	var corners: array<float2>
	var side_direction = float2(-direction.y, direction.x)
	var color_code = make_color(color)
	var side_color_code = make_color(0.8 * color)
	
	var z = 0.05
	
	var front = 0.5 * car_length * direction
	var right = 0.5 * car_width * side_direction
	
	var corners0: float2[4]
	var corners1: float2[4]
	
	corners0[0] = transform(camera, center + front + right)
	corners0[1] = transform(camera, center + front - right)
	corners0[2] = transform(camera, center - front - right)
	corners0[3] = transform(camera, center - front + right)
	
	corners1[0] = transform_at_z(camera, center + front + right, z)
	corners1[1] = transform_at_z(camera, center + front - right, z)
	corners1[2] = transform_at_z(camera, center - front - right, z)
	corners1[3] = transform_at_z(camera, center - front + right, z)
	
	fill_convex_polygon(corners1, color_code)
	
	var poly: float2[4]
	// left side
	if !turns_to_right(center - right - front, center - right + front, car_position)
		poly[0] = corners0[1]
		poly[1] = corners0[2]
		poly[2] = corners1[2]
		poly[3] = corners1[1]
		fill_convex_polygon(poly, side_color_code)
	
	// right side
	if turns_to_right(center + right - front, center + right + front, car_position)
		poly[0] = corners0[3]
		poly[1] = corners0[0]
		poly[2] = corners1[0]
		poly[3] = corners1[3]
		fill_convex_polygon(poly, side_color_code)
		
	// front side
	if !turns_to_right(center + front - right, center + front + right, car_position)
		poly[0] = corners0[0]
		poly[1] = corners0[1]
		poly[2] = corners1[1]
		poly[3] = corners1[0]
		fill_convex_polygon(poly, side_color_code)
		
	// back side
	if turns_to_right(center - front - right, center - front + right, car_position)
		poly[0] = corners0[2]
		poly[1] = corners0[3]
		poly[2] = corners1[3]
		poly[3] = corners1[2]
		fill_convex_polygon(poly, side_color_code)
		
	return
	
def draw_car(camera: Camera; center: float2; direction: float2; color: uint)
	var corners: array<float2>
	var side_direction = float2(direction.y, -direction.x)
	
	var v1 = 0.5 * car_length * direction
	var v2 = 0.5 * car_width * side_direction
	
	push(corners, transform(camera, center + v1 + v2))
	push(corners, transform(camera, center + v1 - v2))
	push(corners, transform(camera, center - v1 - v2))
	push(corners, transform(camera, center - v1 + v2))
	
	fill_convex_polygon(corners, color)
	
def draw_car(camera: Camera; center: float2; angle: float; color: uint)
	var direction = float2(cos(angle), sin(angle))
	draw_car(camera, center, direction, color)
	
def get_random_sidewalk_position(var seed: int4&): float2
	let horizontal_road_n = junction_row_n * (junction_col_n - 1)
	let vertical_road_n = junction_col_n * (junction_row_n - 1)
	let road_n = horizontal_road_n + vertical_road_n
	
	var road_id = random_int(seed) % road_n
		
	var left, right, top, bottom: float
		
	if road_id < horizontal_road_n
		var row = road_id / (junction_col_n - 1)
		var left_col = road_id % (junction_col_n - 1)
		
		left = float(left_col) * (junction_width + road_length) + junction_width
		right = left + road_length
		
		if (random_int(seed) % 2) == 0
			bottom = float(row) * (junction_width + road_length)
			top = bottom - sidewalk_width
		else
			top = float(row) * (junction_width + road_length) + junction_width
			bottom = top + sidewalk_width
	else
		road_id -= horizontal_road_n
		
		var col = road_id / (junction_row_n - 1)
		var top_col = road_id % (junction_row_n - 1)
		
		top = float(top_col) * (junction_width + road_length) + junction_width
		bottom = top + road_length
		
		if (random_int(seed) % 2) == 0
			right = float(col) * (junction_width + road_length)
			left = right - sidewalk_width
		else
			left = float(col) * (junction_width + road_length) + junction_width
			right = left + sidewalk_width

	var result: float2;
	result.x = left + random_float(seed) * (right - left)
	result.y = top + random_float(seed) * (bottom - top)
	return result

def draw_road_rects()
	for junction in junctions
		var left = junction.center.x - 0.5 * junction_width
		var top = junction.center.y - 0.5 * junction_width
		draw_rect(camera, left, top, junction_width, junction_width, road_color)
		
	for road in roads
		var rect: Rect
		if road.p1.x == road.p2.x
			rect.left = road.p1.x - 0.5 * junction_width
			rect.right = road.p1.x + 0.5 * junction_width
			rect.top = min(road.p1.y, road.p2.y)
			rect.bottom = max(road.p1.y, road.p2.y)
		else
			rect.left = min(road.p1.x, road.p2.x)
			rect.right = max(road.p1.x, road.p2.x)
			rect.bottom = road.p1.y - 0.5 * junction_width
			rect.top = road.p1.y + 0.5 * junction_width
		
		draw_rect(camera, rect, road_color)
	return
	
def draw_road_stripes()
	var color = make_color(1.0, 1.0, 1.0)
	
	for junction in junctions
		var rect = rect_center_radius(junction.center, 0.5 * junction_width)
		draw_rect_outline(camera, rect, color)
	
	for road in roads
		draw_line(camera, road.p1, road.p2, color)
		
struct OBB
	center: float2
	direction: float2
	width, length: float
	
struct Quad
	corners: float2[4]
	
struct Line
	p1, p2: float2
	
def get_obb_corners(box: OBB)
	var q: Quad
	var side_direction = turn_to_right(box.direction)
	var front = box.center + 0.5 * box.length * box.direction
	var back = box.center - 0.5 * box.length * box.direction
	
	var side = 0.5 * box.width * side_direction
	q.corners[0] = front - side
	q.corners[1] = front + side
	q.corners[2] = back + side
	q.corners[3] = back - side
	return q
	
def obb_contains_position(box: OBB; position: float2)
	var x = dot(position - box.center, box.direction)
	var y = dot(position - box.center, turn_to_right(box.direction))
	
	var in_x = (abs(x) <= 0.5 * box.length)
	var in_y = (abs(y) <= 0.5 * box.width)
	return (in_x && in_y)
	
def obbs_collide(box1, box2: OBB): bool
	// note: since no boxes are very thin, and we handle collisions anyway
	// we can assume they collide if one contains any corner of the other
	var quad1 = get_obb_corners(box1)
	var quad2 = get_obb_corners(box2)
	
	for i in range(4)
		if obb_contains_position(box1, quad2.corners[i])
			return true
	
	for i in range(4)
		if obb_contains_position(box2, quad1.corners[i])
			return true
	return false
	
struct Collision
	position: float2
	normal: float2
	
def get_min_distance_along_direction(positions: float2[4]; direction: float2)
	var min_dist = dot(direction, positions[0])
	for i in range(1, 4)
		var dist = dot(direction, positions[i])
		min_dist = min(min_dist, dist)
		
	return min_dist
	
def get_max_distance_along_direction(positions: float2[4]; direction: float2)
	var max_dist = dot(direction, positions[0])
	for i in range(1, 4)
		var dist = dot(direction, positions[i])
		max_dist = max(max_dist, dist)
		
	return max_dist
	
def get_closest_position_along_direction(positions: float2[4]; direction: float2)
	var min_dist = dot(direction, positions[0])
	var result = positions[0]
	
	for i in range(1, 4)
		var dist = dot(direction, positions[i])
		if dist < min_dist
			min_dist = dist
			result = positions[i]
	
	return result
	
def get_obb_collision(box1, box2: OBB): Collision
	// note: we assume that this is only called when boxes actually collide
	var quad1 = get_obb_corners(box1)
	var quad2 = get_obb_corners(box2)
	
	var collision: Collision
	var min_dist = 1000.0
	for i in range(4)
		var j = (i < 3) ? (i + 1): 0
		var line: Line
		line.p1 = quad1.corners[i]
		line.p2 = quad1.corners[j]
		
		var left = turn_to_left(line.p2 - line.p1)
		var normal = normalize(left)
		
		var min1 = get_min_distance_along_direction(quad1.corners, normal)
		var max1 = get_max_distance_along_direction(quad1.corners, normal)
		var min2 = get_min_distance_along_direction(quad2.corners, normal)
		var max2 = get_max_distance_along_direction(quad2.corners, normal)
		
		var good = (min1 < min2 && min2 < max1 && max1 < max2)
		if !good
			continue
			
		var dist = max1 - min2;
		if dist < min_dist
			min_dist = dist
			collision.normal = -normal
			collision.position = get_closest_position_along_direction(quad2.corners, normal)
	
	for i in range(4)
		var j = (i < 3) ? (i + 1) : 0
		var line: Line
		line.p1 = quad2.corners[i]
		line.p2 = quad2.corners[j]
		
		var left = turn_to_left(line.p2 - line.p1)
		var normal = normalize(left)
		
		var min1 = get_min_distance_along_direction(quad1.corners, normal)
		var max1 = get_max_distance_along_direction(quad1.corners, normal)
		var min2 = get_min_distance_along_direction(quad2.corners, normal)
		var max2 = get_max_distance_along_direction(quad2.corners, normal)
		
		var good = (min2 < min1 && min1 < max2 && max2 < max1)
		if !good
			continue
			
		var dist = max2 - min1
		if dist < min_dist
			min_dist = dist
			collision.normal = normal
			collision.position = get_closest_position_along_direction(quad1.corners, normal)

	return collision
	
def get_position_velocity(position: float2): float2
	var relative_position = (position - car_position)
	var turn_velocity = car_angular_velocity * turn_to_left(relative_position)
	return car_velocity + turn_velocity
	
def apply_collision(collision: Collision; velocity2: float2)
	// note: we assume that car collides with a static object (i.e. an object with infinite mass)
	// velocity2 is the velocity of the other object

	var hit_point_velocity = get_position_velocity(collision.position)
	var relative_velocity = hit_point_velocity - velocity2
	var turn_force = turn_to_left(collision.position - car_position)
	
	var reflection_ratio = 0.1
	var up = -(1.0 + reflection_ratio) * dot(relative_velocity, collision.normal)
	var down = 1.0 / car_mass + sqr(dot(turn_force, collision.normal)) / car_inertia
	var force_ratio = up / down
	
	if force_ratio > 0.0
		car_velocity += (force_ratio / car_mass) * collision.normal
		car_angular_velocity += dot(turn_force, force_ratio * collision.normal) / car_inertia
	
def draw_obb_outline(camera: Camera; box: OBB; color: uint)
	var corners = get_obb_corners(box)
	draw_line(camera, corners.corners[0], corners.corners[1], color)
	draw_line(camera, corners.corners[1], corners.corners[2], color)
	draw_line(camera, corners.corners[2], corners.corners[3], color)
	draw_line(camera, corners.corners[3], corners.corners[0], color)
	
def rect_center_radius(center: float2; radius: float)
	var rect: Rect
	rect.left = center.x - radius
	rect.right = center.x + radius
	rect.top = center.y - radius
	rect.bottom = center.y + radius
	return rect
	
def semaphore_is_red(road_id, junction_id: int; green_index: int)
	var junction = junctions[junction_id]
	var road_n = 0
	for i in range(4)
		if junction.roads[i] != -1
			road_n++
	
	for i in range(4)
		if junction.roads[i] == road_id
			return (i != (green_index % road_n))
	return true
	
def draw_semaphores(green_index: int; is_yellow: bool)
	for junction_id in range(length(junctions))
		var junction = junctions[junction_id]
		
		var road_n = 0
		for i in range(4)
			if junction.roads[i] != -1
				road_n++
		
		for i in range(4)
			var road_id = junction.roads[i]
			if road_id != -1
				var green = 0x002200
				var yellow = 0x222200
				var red = 0x220000
				
				if i == (green_index % road_n)
					if is_yellow
						yellow = 0xFFFF00
					else
						green = 0x00FF00
				else
					red = 0xFF0000
			
				var dir = get_junction_enter_direction(junction_id, road_id)
			
				var position = 0.5 * (get_junction_enter_position(junction_id, road_id, 0) + get_junction_enter_position(junction_id, road_id, 1))
			
				var position1 = position - 2.0 * dir	
				var side_dir = turn_to_right(dir)
				var position0 = position1 - 3.0 * side_dir
				var position2 = position1 + 3.0 * side_dir
				
				var rect0 = rect_center_radius(position0, 1.0)
				draw_rect(camera, rect0, red)
				
				var rect1 = rect_center_radius(position1, 1.0)
				draw_rect(camera, rect1, yellow)
				
				var rect2 = rect_center_radius(position2, 1.0)
				draw_rect(camera, rect2, green)
	
def draw_text_centered(x, y: float; text: string; color: uint)
	var size = get_text_size(text)
	text_out(x - 0.5 * size.x + 1.0, y + 1.0, text, 0x000000)
	text_out(x - 0.5 * size.x, y, text, color)
	
def draw_text_right(x, y: float; text: string; color: uint)
	var size = get_text_size(text)
	text_out(x - size.x + 1.0, y + 1.0, text, 0x000000)
	text_out(x - size.x, y, text, color)
	
[export]
def draw
	var visible_rect = get_visible_rect(camera)
	draw_rect(camera, visible_rect, sidewalk_color)

	draw_road_rects()
	draw_road_stripes()
	draw_semaphores(semaphore_index, semaphore_time > 4.0)
	
	if pedestrian_picked_up
		if rect_contains_position(visible_rect, target_position)
			if tutorial_index == 3
				tutorial_index = 4
				
			var color = target_color
			if tutorial_index == 4
				var color2 = float3(0.5, 0.5, 0.0)
				color = lerp(color, color2, tutorial_lerp_ratio)
			
			draw_circle(camera, target_position, pedestrian_pick_up_radius, make_color(color))
	
	draw_car(camera, car_position, car_angle, car_color)
	
	for car in cars
		draw_car_3d(camera, car.position, car.direction, car.color)
	
	var color = pedestrian_color
	if tutorial_index == 1
		var color2 = float3(0.0, 1.0, 1.0)
		color = lerp(color, color2, tutorial_lerp_ratio)

	for i in range(pedestrian_n)
		var p = pedestrian_positions[i]
		var rect = rect_center_radius(p, pedestrian_radius)
		if i != highlighted_pedestrian_id
			draw_rect_3d(camera, rect, 0.1, color)
		else
			color = pedestrian_color
			if tutorial_index == 2
				var color2 = float3(0.0, 1.0, 1.0)
				color = lerp(color, color2, tutorial_lerp_ratio)
				
			draw_circle(camera, p, pedestrian_pick_up_radius, make_color(color))
			draw_rect_3d(camera, rect, 0.1, color)
			
	for building in buildings
		draw_rect_3d(camera, building.rect, building.height, building.color)
		
	if pedestrian_picked_up
		if !rect_contains_position(visible_rect, target_position)
			var screen_size = camera.screen_size
			var screen_center = 0.5 * screen_size
			var direction = normalize(target_position - car_position)
			var skewed_direction = float2(direction.x / screen_size.x, direction.y / screen_size.y)
			
			var arrow_point: float2
			var abs_x = abs(skewed_direction.x)
			var abs_y = abs(skewed_direction.y)
			
			if abs_y > abs_x
				if skewed_direction.y > 0.0
					arrow_point = screen_center + (0.5 * screen_size.y) * (1.0 / direction.y) * direction
				else
					arrow_point = screen_center - (0.5 * screen_size.y) * (1.0 / direction.y) * direction
			else
				if skewed_direction.x > 0.0
					arrow_point = screen_center + (0.5 * screen_size.x) * (1.0 / direction.x) * direction
				else
					arrow_point = screen_center - (0.5 * screen_size.x) * (1.0 / direction.x) * direction
			
			var arrow_dir = normalize(arrow_point - screen_center)
			var side_dir = turn_to_right(arrow_dir)
			var arrow_base = arrow_point - 50.0 * arrow_dir
			
			var poly: float2[3]
			poly[0] = arrow_point
			poly[1] = arrow_base - 50.0f * side_dir
			poly[2] = arrow_base + 50.0f * side_dir
			
			color = target_color
			if tutorial_index == 3
				var color2 = float3(0.5, 0.5, 0.0)
				color = lerp(color, color2, tutorial_lerp_ratio)
			
			fill_convex_polygon(poly, make_color(color))
			
	set_font_size(20)
	var screen_size = camera.screen_size
	var screen_center = 0.5 * screen_size
	if tutorial_index == 0
		var welcome_text = "Welcome! In this game you will drive a taxi."
		draw_text_centered(screen_center.x, screen_center.y - 230.0, welcome_text, 0xFFFFFF)
		draw_text_centered(screen_center.x, screen_center.y - 200.0, "Use [WASD] or [Arrow keys] to drive!", 0xFFFFFF)
	elif tutorial_index == 1
		draw_text_centered(screen_center.x, screen_center.y - 200.0, "Drive close to a pedestrian to start service!", 0xFFFFFF)
	elif tutorial_index == 2
		draw_text_centered(screen_center.x, screen_center.y - 200.0, "Stop nearby to pick up client!", 0xFFFFFF)
	elif tutorial_index == 3
		draw_text_centered(screen_center.x, screen_center.y - 200.0, "Drive your client to the target position!", 0xFFFFFF)
	elif tutorial_index == 4
		draw_text_centered(screen_center.x, screen_center.y - 200.0, "Stop inside target circle!", 0xFFFFFF)
	elif tutorial_index == 5
		var text = "Drive fast and avoid collisions to get a high score!"
		draw_text_centered(screen_center.x, screen_center.y - 200.0, text, 0xFFFFFF)

	var time = int(time_remaining)
	var minutes = time / 60
	var minute1 = minutes / 10
	var minute2 = minutes % 10
	
	var seconds = time % 60
	var second1 = seconds / 10
	var second2 = seconds % 10
		
	var time_text = "Time: {minute1}{minute2}:{second1}{second2}"
	draw_text_right(screen_size.x - 30.0, 10.0, time_text, 0xFFFFFF)
	draw_text_right(screen_size.x - 30.0, 40.0, "Score: {score}", 0xFFFF00)
	if pedestrian_picked_up
		draw_text_right(screen_size.x - 30.0, 70.0, "Current: {current_score}", 0xAAAA00)
		
		set_font_size(15)
		var x = 100.0
		if speed_bonus >= 1.0
			var color1 = float3(0.0, 1.0, 0.0)
			var color2 = float3(0.0, 0.8, 0.0)
			color = lerp(color1, color2, tutorial_lerp_ratio)
		
			var speed_bonus_int = int(speed_bonus)
			draw_text_right(screen_size.x - 30.0, x, "Speed bonus: {speed_bonus_int}!", make_color(color))
			x += 20.0
		if collision_penalty_time > 0.0
			var color1 = float3(1.0, 0.0, 0.0)
			var color2 = float3(0.8, 0.0, 0.0)
			color = lerp(color1, color2, tutorial_lerp_ratio)
		
			draw_text_right(screen_size.x - 30.0, x, "Collision: -{collision_penalty}!", make_color(color))
			x += 20.0
			
	if time_remaining == 0.0
		set_font_size(50)
		draw_text_centered(screen_center.x, screen_center.y - 30.0, "Game Over", 0xFFFFFF)
		set_font_size(30)
		draw_text_centered(screen_center.x, screen_center.y + 30.0, "Your score: {score}", 0x00AA00)
		
		set_font_size(20)
		draw_text_centered(screen_center.x, screen_center.y + 80.0, "[Enter] Play again", 0xCCCCCC)
		draw_text_centered(screen_center.x, screen_center.y + 100.0, "[Esc] Quit", 0xCCCCCC)
		
    return
