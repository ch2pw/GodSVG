## Contours drawing and [Handle]s are managed here. 
extends Control

const handle_texture_dir = "res://visual/icons/handles/%s.svg"

const normal_handle_textures = {
	Handle.Display.BIG: preload(handle_texture_dir % "HandleBig"),
	Handle.Display.SMALL: preload(handle_texture_dir % "HandleSmall"),
}

const hovered_handle_textures = {
	Handle.Display.BIG: preload(handle_texture_dir % "HandleBigHovered"),
	Handle.Display.SMALL: preload(handle_texture_dir % "HandleSmallHovered"),
}

const selected_handle_textures = {
	Handle.Display.BIG: preload(handle_texture_dir % "HandleBigSelected"),
	Handle.Display.SMALL: preload(handle_texture_dir % "HandleSmallSelected"),
}

const hovered_selected_handle_textures = {
	Handle.Display.BIG: preload(handle_texture_dir % "HandleBigHoveredSelected"),
	Handle.Display.SMALL: preload(handle_texture_dir % "HandleSmallHoveredSelected"),
}

const default_color_string = "#000"
const hover_color_string = "#aaa"
const selection_color_string = "#46f"
const hover_selection_color_string = "#f44"
const default_color = Color(default_color_string)
const hover_color = Color(hover_color_string)
const selection_color = Color(selection_color_string)
const hover_selection_color = Color(hover_selection_color_string)

var update_pending := false

var handles: Array[Handle]

var surface := RenderingServer.canvas_item_create()

func _ready() -> void:
	RenderingServer.canvas_item_set_parent(surface, get_canvas_item())
	SVG.root_tag.attribute_changed.connect(queue_update.unbind(1))
	SVG.root_tag.child_attribute_changed.connect(queue_redraw.unbind(1))
	SVG.root_tag.child_attribute_changed.connect(sync_handles.unbind(1))
	SVG.root_tag.tag_layout_changed.connect(queue_update)
	SVG.root_tag.changed_unknown.connect(queue_update)
	Indications.selection_changed.connect(queue_redraw)
	Indications.hover_changed.connect(queue_redraw)
	Indications.zoom_changed.connect(queue_redraw)
	Indications.added_path_handle.connect(move_selected_to_mouse)
	queue_update()


func queue_update() -> void:
	update_pending = true

func _process(_delta: float) -> void:
	if update_pending:
		update_handles()
		update_pending = false


func update_handles() -> void:
	handles.clear()
	for tid in SVG.root_tag.get_all_tids():
		var tag := SVG.root_tag.get_by_tid(tid)
		match tag.name:
			"circle":
				handles.append(generate_xy_handle(tid, tag, "cx", "cy", "transform"))
				handles.append(generate_delta_handle(tid, tag, "cx", "cy", "transform", "r", true))
			"ellipse":
				handles.append(generate_xy_handle(tid, tag, "cx", "cy", "transform"))
				handles.append(generate_delta_handle(tid, tag, "cx", "cy", "transform", "rx", true))
				handles.append(generate_delta_handle(tid, tag, "cx", "cy", "transform", "ry", false))
			"rect":
				handles.append(generate_xy_handle(tid, tag, "x", "y", "transform"))
				handles.append(generate_xy_handle(tid, tag, "x", "y", "transform"))
				handles.append(generate_delta_handle(tid, tag, "x", "y", "transform", "width", true))
				handles.append(generate_delta_handle(tid, tag, "x", "y", "transform", "height", false))
			"line":
				handles.append(generate_xy_handle(tid, tag, "x1", "y1", "transform"))
				handles.append(generate_xy_handle(tid, tag, "x2", "y2", "transform"))
			"path":
				handles += generate_path_handles(tid, tag.attributes.d, tag.attributes.transform)
	queue_redraw()


func sync_handles() -> void:
	# For XYHandles, sync them. For PathHandles, sync all but the one being dragged.
	for handle_idx in range(handles.size() - 1, -1, -1):
		var handle := handles[handle_idx]
		if handle is PathHandle:
			if dragged_handle != handle:
				handles.remove_at(handle_idx)
		else:
			handle.sync()
	
	var tids := SVG.root_tag.get_all_tids()
	
	for tid in tids:
		var tag := SVG.root_tag.get_by_tid(tid)
		if tag.name == "path":
			handles += generate_path_handles(tid, tag.attributes.d, tag.attributes.transform)
	queue_redraw()

func generate_path_handles(tid: PackedInt32Array,
path_attribute: AttributePath, transform_attribute: AttributeTransform) -> Array[Handle]:
	var path_handles: Array[Handle] = []
	for idx in path_attribute.get_command_count():
		var path_command := path_attribute.get_command(idx)
		if path_command.command_char.to_upper() != "Z":
			path_handles.append(PathHandle.new(tid, path_attribute, transform_attribute, idx))
			if path_command.command_char.to_upper() in "CQ":
				var tangent := PathHandle.new(tid, path_attribute, transform_attribute, idx, &"x1", &"y1")
				tangent.display_mode = Handle.Display.SMALL
				path_handles.append(tangent)
			if path_command.command_char.to_upper() in "CS":
				var tangent := PathHandle.new(tid, path_attribute, transform_attribute, idx, &"x2", &"y2")
				tangent.display_mode = Handle.Display.SMALL
				path_handles.append(tangent)
	return path_handles

# The place where these are used, a tag is already at hand, so no need to find it.
func generate_xy_handle(tid: PackedInt32Array, tag: Tag, x_attrib_name: String,\
y_attrib_name: String, t_attrib_name: String) -> XYHandle:
	var new_handle := XYHandle.new(tid, tag.attributes[x_attrib_name],
			tag.attributes[y_attrib_name], tag.attributes[t_attrib_name])
	new_handle.tag = tag
	return new_handle

func generate_delta_handle(tid: PackedInt32Array, tag: Tag, x_attrib_name: String,\
y_attrib_name: String, t_attrib_name: String, delta_attrib_name: String, horizontal: bool) -> DeltaHandle:
	var new_handle := DeltaHandle.new(tid, tag.attributes[x_attrib_name],
			tag.attributes[y_attrib_name], tag.attributes[t_attrib_name], tag.attributes[delta_attrib_name], horizontal)
	new_handle.tag = tag
	return new_handle


func _draw() -> void:
	# Store contours of shapes.
	var normal_polylines: Array[PackedVector2Array] = []
	var selected_polylines: Array[PackedVector2Array] = []
	var hovered_polylines: Array[PackedVector2Array] = []
	var hovered_selected_polylines: Array[PackedVector2Array] = []
	# Store abstract contours, e.g. tangents.
	var normal_multiline := PackedVector2Array()
	var selected_multiline := PackedVector2Array()
	var hovered_multiline := PackedVector2Array()
	var hovered_selected_multiline := PackedVector2Array()
	
	var tids := SVG.root_tag.get_all_tids()
	
	for tid in tids:
		var tag := SVG.root_tag.get_by_tid(tid)
		var attribs := tag.attributes
		
		# Determine if the tag is hovered/selected or has a hovered/selected parent.
		var tag_hovered := tid_is_hovered(tid, -1)
		var tag_selected := tid_is_selected(tid, -1)
		
		match tag.name:
			"circle":
				var c := Vector2(attribs.cx.get_num(), attribs.cy.get_num())
				var r: float = attribs.r.get_num()
				
				var points := PackedVector2Array()
				points.resize(181)
				for i in 180:
					var d := i * TAU/180
					points[i] = c + Vector2(cos(d), sin(d)) * r
				points[180] = points[0]
				var extras := PackedVector2Array([c, c + Vector2(r, 0)])
				points = attribs.transform.get_final_transform() * points
				extras = attribs.transform.get_final_transform() * extras
				
				if tag_hovered and tag_selected:
					hovered_selected_polylines.append(points)
					hovered_selected_multiline += extras
				elif tag_hovered:
					hovered_polylines.append(points)
					hovered_multiline += extras
				elif tag_selected:
					selected_polylines.append(points)
					selected_multiline += extras
				else:
					normal_polylines.append(points)
					normal_multiline += extras
			
			"ellipse":
				var c := Vector2(attribs.cx.get_num(), attribs.cy.get_num())
				var rx: float = attribs.rx.get_num()
				var ry: float = attribs.ry.get_num()
				# Squished circle.
				var points := PackedVector2Array()
				points.resize(181)
				for i in 180:
					var d := i * TAU/180
					points[i] = c + Vector2(cos(d) * rx, sin(d) * ry)
				points[180] = points[0]
				var extras := PackedVector2Array([
						c, c + Vector2(rx, 0), c, c + Vector2(0, ry)])
				points = attribs.transform.get_final_transform() * points
				extras = attribs.transform.get_final_transform() * extras
				
				if tag_hovered and tag_selected:
					hovered_selected_polylines.append(points)
					hovered_selected_multiline += extras
				elif tag_hovered:
					hovered_polylines.append(points)
					hovered_multiline += extras
				elif tag_selected:
					selected_polylines.append(points)
					selected_multiline += extras
				else:
					normal_polylines.append(points)
					normal_multiline += extras
			
			"rect":
				var x: float = attribs.x.get_num()
				var y: float = attribs.y.get_num()
				var rect_width: float = attribs.width.get_num()
				var rect_height: float = attribs.height.get_num()
				var rx: float = attribs.rx.get_num()
				var ry: float = attribs.ry.get_num()
				var points := PackedVector2Array()
				if rx == 0 and ry == 0:
					# Basic rectangle.
					points = [Vector2(x, y), Vector2(x + rect_width, y),
							Vector2(x + rect_width, y + rect_height),
							Vector2(x, y + rect_height), Vector2(x, y)]
				else:
					if rx == 0:
						rx = ry
					elif ry == 0:
						ry = rx
					rx = minf(rx, rect_width / 2)
					ry = minf(ry, rect_height / 2)
					# Rounded rectangle.
					points.resize(186)
					points[0] = Vector2(x + rx, y)
					points[1] = Vector2(x + rect_width - rx, y)
					for i in range(135, 180):
						var d := i * TAU/180
						points[i - 133] = Vector2(x + rect_width - rx, y + ry) +\
								Vector2(cos(d) * rx, sin(d) * ry)
					points[47] =  Vector2(x + rect_width, y + rect_height - ry)
					for i in range(0, 45):
						var d := i * TAU/180
						points[i + 48] = Vector2(x + rect_width - rx, y + rect_height - ry) +\
								Vector2(cos(d) * rx, sin(d) * ry)
					points[93] = Vector2(x + rx, y + rect_height)
					for i in range(45, 90):
						var d := i * TAU/180
						points[i + 49] = Vector2(x + rx, y + rect_height - ry) +\
								Vector2(cos(d) * rx, sin(d) * ry)
					points[139] = Vector2(x, y + ry)
					for i in range(90, 135):
						var d := i * TAU/180
						points[i + 50] = Vector2(x + rx, y + ry) +\
								Vector2(cos(d) * rx, sin(d) * ry)
					points[185] = points[0]
				var extras := PackedVector2Array([Vector2(x, y), Vector2(x + rect_width, y),
						Vector2(x, y), Vector2(x, y + rect_height)])
				points = attribs.transform.get_final_transform() * points
				extras = attribs.transform.get_final_transform() * extras
				
				if tag_hovered and tag_selected:
					hovered_selected_polylines.append(points)
					hovered_selected_multiline += extras
				elif tag_hovered:
					hovered_polylines.append(points)
					hovered_multiline += extras
				elif tag_selected:
					selected_polylines.append(points)
					selected_multiline += extras
				else:
					normal_polylines.append(points)
					normal_multiline += extras
			
			"line":
				var x1: float = attribs.x1.get_num()
				var y1: float = attribs.y1.get_num()
				var x2: float = attribs.x2.get_num()
				var y2: float = attribs.y2.get_num()
				
				var points := PackedVector2Array([Vector2(x1, y1), Vector2(x2, y2)])
				points = attribs.transform.get_final_transform() * points
				
				if tag_hovered and tag_selected:
					hovered_selected_polylines.append(points)
				elif tag_hovered:
					hovered_polylines.append(points)
				elif tag_selected:
					selected_polylines.append(points)
				else:
					normal_polylines.append(points)
			
			"path":
				var pathdata: AttributePath = attribs.d
				if pathdata.get_command_count() == 0 or\
				pathdata.get_command(0).command_char.to_upper() != "M":
					continue  # Nothing to draw.
				
				var current_mode := Utils.InteractionType.NONE
				
				for cmd_idx in pathdata.get_command_count():
					# Drawing logic.
					var points := PackedVector2Array()
					var tangent_points := PackedVector2Array()
					var cmd := pathdata.get_command(cmd_idx)
					var relative := cmd.relative
					
					current_mode = Utils.InteractionType.NONE
					if tid_is_hovered(tid, cmd_idx):
						@warning_ignore("int_as_enum_without_cast")
						current_mode += Utils.InteractionType.HOVERED
					if tid_is_selected(tid, cmd_idx):
						@warning_ignore("int_as_enum_without_cast")
						current_mode += Utils.InteractionType.SELECTED
					
					match cmd.command_char.to_upper():
						"L":
							# Line contour.
							var v := Vector2(cmd.x, cmd.y)
							var end := cmd.start + v if relative else v
							points = PackedVector2Array([cmd.start, end])
						"H":
							# Horizontal line contour.
							var v := Vector2(cmd.x, 0)
							var end := cmd.start + v if relative else Vector2(v.x, cmd.start.y)
							points = PackedVector2Array([cmd.start, end])
						"V":
							# Vertical line contour.
							var v := Vector2(0, cmd.y)
							var end := cmd.start + v if relative else Vector2(cmd.start.x, v.y)
							points = PackedVector2Array([cmd.start, end])
						"C":
							# Cubic Bezier curve contour.
							var v := Vector2(cmd.x, cmd.y)
							var v1 := Vector2(cmd.x1, cmd.y1)
							var v2 := Vector2(cmd.x2, cmd.y2)
							var cp1 := cmd.start
							var cp4 := cp1 + v if relative else v
							var cp2 := v1 if relative else v1 - cp1
							var cp3 := v2 - v
							
							points = Utils.get_cubic_bezier_points(cp1, cp2, cp3, cp4)
							tangent_points.append_array(PackedVector2Array([cp1,
									cp1 + cp2, cp1 + v2 if relative else v2, cp4]))
						"S":
							# Shorthand cubic Bezier curve contour.
							if cmd_idx == 0:
								break
							var prev_cmd := pathdata.get_command(cmd_idx - 1)
							
							var v := Vector2(cmd.x, cmd.y)
							var v1 := Vector2() if relative else cmd.start
							if prev_cmd.command_char.to_upper() in "CS":
								var prev_control_pt := Vector2(prev_cmd.x2, prev_cmd.y2)
								if prev_cmd.relative:
									v1 = cmd.start - prev_control_pt - prev_cmd.start if relative\
											else cmd.start * 2 - prev_control_pt - prev_cmd.start
								else:
									v1 = cmd.start - prev_control_pt if relative\
											else cmd.start * 2 - prev_control_pt
							var v2 := Vector2(cmd.x2, cmd.y2)
							
							var cp1 := cmd.start
							var cp4 := cp1 + v if relative else v
							var cp2 := v1 if relative else v1 - cp1
							var cp3 := v2 - v
							
							points = Utils.get_cubic_bezier_points(cp1, cp2, cp3, cp4)
							tangent_points.append_array(PackedVector2Array([cp1,
									cp1 + cp2, cp1 + v2 if relative else v2, cp4]))
						"Q":
							# Quadratic Bezier curve contour.
							var v := Vector2(cmd.x, cmd.y)
							var v1 := Vector2(cmd.x1, cmd.y1)
							var cp1 := cmd.start
							var cp2 := cp1 + v1 if relative else v1
							var cp3 := cp1 + v if relative else v
							
							points = Utils.get_quadratic_bezier_points(cp1, cp2, cp3)
							tangent_points.append_array(PackedVector2Array([cp1, cp2, cp2, cp3]))
						"T":
							# Shorthand quadratic Bezier curve contour.
							var prevQ_idx := cmd_idx - 1
							var prevQ_cmd := pathdata.get_command(prevQ_idx)
							while prevQ_idx >= 0:
								if prevQ_cmd.command_char.to_upper() != "T":
									break
								elif prevQ_cmd.command_char.to_upper() != "T":
									# Invalid T is drawn as a line.
									var end := cmd.start + Vector2(cmd.x, cmd.y) if relative\
											else Vector2(cmd.x, cmd.y)
									points.append(cmd.start)
									points.append(end)
									prevQ_idx = -1
									break
								else:
									prevQ_idx -= 1
									prevQ_cmd = pathdata.get_command(prevQ_idx)
							if prevQ_idx == -1:
								continue
							
							var prevQ_x: float = prevQ_cmd.x if &"x" in prevQ_cmd\
									else prevQ_cmd.start.x
							var prevQ_y: float = prevQ_cmd.y if &"y" in prevQ_cmd\
									else prevQ_cmd.start.y
							var prevQ_v := Vector2(prevQ_x, prevQ_y)
							var prevQ_v1 := Vector2(prevQ_cmd.x1, prevQ_cmd.y1) if\
									prevQ_cmd.command_char.to_upper() == "Q" else prevQ_v
							var prevQ_end := prevQ_cmd.start + prevQ_v\
									if prevQ_cmd.relative else prevQ_v
							var prevQ_control_pt := prevQ_cmd.start + prevQ_v1\
									if prevQ_cmd.relative else prevQ_v1
							
							
							var v := Vector2(cmd.x, cmd.y)
							var v1 := prevQ_end * 2 - prevQ_control_pt
							for T_idx in range(prevQ_idx + 1, cmd_idx):
								var T_cmd := pathdata.get_command(T_idx)
								var T_v := Vector2(T_cmd.x, T_cmd.y)
								var T_end := T_cmd.start + T_v if T_cmd.relative else T_v
								v1 = T_end * 2 - v1
							
							var cp1 := cmd.start
							var cp2 := v1
							var cp3 := cp1 + v if relative else v
							
							points = Utils.get_quadratic_bezier_points(cp1, cp2, cp3)
							tangent_points.append_array(PackedVector2Array([cp1, cp2, cp2, cp3]))
						"A":
							# Elliptical arc contour.
							var start := cmd.start
							var v := Vector2(cmd.x, cmd.y)
							var end := start + v if relative else v
							# Correct for out-of-range radii.
							if start == end:
								continue
							elif cmd.rx == 0 or cmd.ry == 0:
								points = PackedVector2Array([start, end])
							
							var r := Vector2(cmd.rx, cmd.ry).abs()
							# Obtain center parametrization.
							var rot := deg_to_rad(cmd.rot)
							var cosine := cos(rot)
							var sine := sin(rot)
							var half := (start - end) / 2
							var x1 := half.x * cosine + half.y * sine
							var y1 := -half.x * sine + half.y * cosine
							var r2 := Vector2(r.x * r.x, r.y * r.y)
							var x12 := x1 * x1
							var y12 := y1 * y1
							var cr := x12 / r2.x + y12 / r2.y
							if cr > 1:
								cr = sqrt(cr)
								r *= cr
								r2 = Vector2(r.x * r.x, r.y * r.y)
							
							var dq := r2.x * y12 + r2.y * x12
							var pq := (r2.x * r2.y - dq) / dq
							var sc := sqrt(maxf(0, pq))
							if cmd.large_arc_flag == cmd.sweep_flag:
								sc = -sc
							
							var ct := Vector2(r.x * sc * y1 / r.y, -r.y * sc * x1 / r.x)
							var c := Vector2(ct.x * cosine - ct.y * sine,
									ct.x * sine + ct.y * cosine) + start.lerp(end, 0.5)
							var tv := Vector2(x1 - ct.x, y1 - ct.y) / r
							var theta1 := tv.angle()
							var delta_theta := fposmod(tv.angle_to(
									Vector2(-x1 - ct.x, -y1 - ct.y) / r), TAU)
							if cmd.sweep_flag == 0:
								theta1 += delta_theta
								delta_theta = TAU - delta_theta
							
							# Now we have a center parametrization (r, c, theta1, delta_theta).
							# We will approximate the elliptical arc with Bezier curves.
							# Use the method described in https://www.blog.akhil.cc/ellipse
							# (but with modifications because it wasn't working fully).
							var segments := delta_theta * 4/PI
							var n := floori(segments)
							var p1 := Utils.E(c, r, cosine, sine, theta1)
							var e1 := Utils.Et(r, cosine, sine, theta1)
							var alpha := 0.26511478
							var t := theta1 + PI/4
							var cp: Array[PackedVector2Array] = []
							for _i in n:
								var p2 := Utils.E(c, r, cosine, sine, t)
								var e2 := Utils.Et(r, cosine, sine, t)
								var q1 := alpha * e1
								var q2 := -alpha * e2
								cp.append(PackedVector2Array([p1, q1, q2, p2]))
								p1 = p2
								e1 = e2
								t += PI/4
							
							if n != ceili(segments):
								t = theta1 + delta_theta
								var p2 := Utils.E(c, r, cosine, sine, t)
								var e2 := Utils.Et(r, cosine, sine, t)
								alpha *= fposmod(delta_theta, PI/4) / (PI/4)
								var q1 := alpha * e1
								var q2 := -alpha * e2
								cp.append(PackedVector2Array([p1, q1, q2, p2]))
							
							for p in cp:
								points += Utils.get_cubic_bezier_points(p[0], p[1], p[2], p[3])
						"Z":
							# Path closure contour.
							var prev_M_idx := cmd_idx - 1
							var prev_M_cmd := pathdata.get_command(prev_M_idx)
							while prev_M_idx >= 0:
								if prev_M_cmd.command_char.to_upper() == "M":
									break
								prev_M_idx -= 1
								prev_M_cmd = pathdata.get_command(prev_M_idx)
							if prev_M_idx == -1:
								break
							
							var end := Vector2(prev_M_cmd.x, prev_M_cmd.y)
							if prev_M_cmd.relative:
								end += prev_M_cmd.start
							
							points = PackedVector2Array([cmd.start, end])
						_: continue
					points = attribs.transform.get_final_transform() * points
					tangent_points = attribs.transform.get_final_transform() * tangent_points
					match current_mode:
						Utils.InteractionType.NONE:
							normal_polylines.append(points.duplicate())
							normal_multiline += tangent_points.duplicate()
						Utils.InteractionType.HOVERED:
							hovered_polylines.append(points.duplicate())
							hovered_multiline += tangent_points.duplicate()
						Utils.InteractionType.SELECTED:
							selected_polylines.append(points.duplicate())
							selected_multiline += tangent_points.duplicate()
						Utils.InteractionType.HOVERED_SELECTED:
							hovered_selected_polylines.append(points.duplicate())
							hovered_selected_multiline += tangent_points.duplicate()
	
	var draw_zoom := Indications.zoom * SVG.root_tag.canvas_transform.get_scale().x
	var contour_width := 1.0 / draw_zoom
	var tangent_width := 0.6 / draw_zoom
	var tangent_alpha := 0.8
	draw_set_transform_matrix(SVG.root_tag.canvas_transform)
	RenderingServer.canvas_item_set_transform(surface, Transform2D(0.0,
			Vector2(1 / Indications.zoom, 1 / Indications.zoom), 0.0, Vector2.ZERO))
	
	for polyline in normal_polylines:
		draw_polyline(polyline, default_color, contour_width, true)
	for polyline in selected_polylines:
		draw_polyline(polyline, selection_color, contour_width, true)
	for polyline in hovered_polylines:
		draw_polyline(polyline, hover_color, contour_width, true)
	for polyline in hovered_selected_polylines:
		draw_polyline(polyline, hover_selection_color, contour_width, true)
	
	draw_multiline_antaliased(normal_multiline,
			Color(default_color, tangent_alpha), tangent_width)
	draw_multiline_antaliased(selected_multiline,
			Color(selection_color, tangent_alpha), tangent_width)
	draw_multiline_antaliased(hovered_multiline,
			Color(hover_color, tangent_alpha), tangent_width)
	draw_multiline_antaliased(hovered_selected_multiline,
			Color(hover_selection_color, tangent_alpha), tangent_width)
	
	# First gather all handles in 4 categories, then draw them in the right order.
	var normal_handles: Array[Handle] = []
	var selected_handles: Array[Handle] = []
	var hovered_handles: Array[Handle] = []
	var hovered_selected_handles: Array[Handle] = []
	for handle in handles:
		var cmd_idx: int = handle.command_index if handle is PathHandle else -1
		var is_hovered := tid_is_hovered(handle.tid, cmd_idx)
		var is_selected := tid_is_selected(handle.tid, cmd_idx)
		
		if is_hovered and is_selected:
			hovered_selected_handles.append(handle)
		elif is_hovered:
			hovered_handles.append(handle)
		elif is_selected:
			selected_handles.append(handle)
		else:
			normal_handles.append(handle)
	
	RenderingServer.canvas_item_clear(surface)
	for handle in normal_handles:
		var texture: Texture2D = normal_handle_textures[handle.display_mode]
		texture.draw(surface, SVG.root_tag.canvas_to_world(handle.transform * handle.pos) *\
				Indications.zoom - texture.get_size() / 2)
	for handle in selected_handles:
		var texture: Texture2D = selected_handle_textures[handle.display_mode]
		texture.draw(surface, SVG.root_tag.canvas_to_world(handle.transform * handle.pos) *\
				Indications.zoom - texture.get_size() / 2)
	for handle in hovered_handles:
		var texture: Texture2D = hovered_handle_textures[handle.display_mode]
		texture.draw(surface, SVG.root_tag.canvas_to_world(handle.transform * handle.pos) *\
				Indications.zoom - texture.get_size() / 2)
	for handle in hovered_selected_handles:
		var texture: Texture2D = hovered_selected_handle_textures[handle.display_mode]
		texture.draw(surface, SVG.root_tag.canvas_to_world(handle.transform * handle.pos) *\
				Indications.zoom - texture.get_size() / 2)

# TODO remove this when it's implemented in Godot.
func draw_multiline_antaliased(points: PackedVector2Array, color: Color,
width: float) -> void:
	for i in int(points.size() / 2.0):
		var i2 := i * 2
		draw_line(points[i2], points[i2 + 1], color, width, true)


func tid_is_hovered(tid: PackedInt32Array, cmd_idx := -1) -> bool:
	if cmd_idx == -1:
		return Utils.is_tid_parent(Indications.hovered_tid, tid) or\
				tid == Indications.hovered_tid
	else:
		return (Utils.is_tid_parent(Indications.hovered_tid, tid) or\
				tid == Indications.hovered_tid) or (Indications.semi_hovered_tid == tid and\
				Indications.inner_hovered == cmd_idx)

func tid_is_selected(tid: PackedInt32Array, cmd_idx := -1) -> bool:
	if cmd_idx == -1:
		for selected_tid in Indications.selected_tids:
			if Utils.is_tid_parent(selected_tid, tid) or tid == selected_tid:
				return true
		return false
	else:
		for selected_tid in Indications.selected_tids:
			if Utils.is_tid_parent(selected_tid, tid) or selected_tid == tid:
				return true
		return Indications.semi_selected_tid == tid and\
				cmd_idx in Indications.inner_selections


var dragged_handle: Handle = null
var hovered_handle: Handle = null
var was_handle_moved := false
var should_deselect_all = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	
	var snap_enabled := GlobalSettings.save_data.snap > 0.0
	var snap_size := absf(GlobalSettings.save_data.snap)
	var snap_vector := Vector2(snap_size, snap_size)
	
	if event is InputEventMouseMotion:
		should_deselect_all = false
		var event_pos: Vector2 = event.position / Indications.zoom +\
				get_node(^"../..").view.position
		if dragged_handle != null:
			# Move the handle that's being dragged.
			if snap_enabled:
				event_pos = event_pos.snapped(snap_vector)
			
			var new_pos := dragged_handle.transform.affine_inverse() * SVG.root_tag.world_to_canvas(event_pos)
			dragged_handle.set_pos(new_pos)
			was_handle_moved = true
			accept_event()
		elif event.button_mask == 0:
			var nearest_handle := find_nearest_handle(event_pos)
			if nearest_handle != null:
				hovered_handle = nearest_handle
				if hovered_handle is PathHandle:
					Indications.set_inner_hovered(hovered_handle.tid,
							hovered_handle.command_index)
				else:
					Indications.set_hovered(hovered_handle.tid)
			else:
				hovered_handle = null
				Indications.clear_hovered()
				Indications.clear_inner_hovered()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var event_pos: Vector2 = event.position / Indications.zoom +\
				get_node(^"../..").view.position
		var nearest_handle := find_nearest_handle(event_pos)
		if nearest_handle != null:
			hovered_handle = nearest_handle
			if hovered_handle is PathHandle:
				Indications.set_inner_hovered(hovered_handle.tid,
						hovered_handle.command_index)
			else:
				Indications.set_hovered(hovered_handle.tid)
		else:
			hovered_handle = null
			Indications.clear_hovered()
			Indications.clear_inner_hovered()
		# React to LMB actions.
		if hovered_handle != null and event.is_pressed():
			dragged_handle = hovered_handle
			dragged_handle.initial_pos = dragged_handle.pos
			var inner_idx = -1
			var dragged_tid := dragged_handle.tid
			if hovered_handle is PathHandle:
				inner_idx = hovered_handle.command_index
			
			if event.double_click and hovered_handle is PathHandle:
				Indications.clear_inner_selection()
				var subpath_range: Vector2i =\
						hovered_handle.path_attribute.get_subpath(inner_idx)
				for idx in range(subpath_range.x, subpath_range.y + 1):
					Indications.ctrl_select(dragged_tid, idx)
			elif event.ctrl_pressed:
				Indications.ctrl_select(dragged_tid, inner_idx)
			elif event.shift_pressed:
				Indications.shift_select(dragged_tid, inner_idx)
			else:
				Indications.normal_select(dragged_tid, inner_idx)
		
		elif dragged_handle != null and event.is_released():
			if was_handle_moved:
				if snap_enabled:
					event_pos = event_pos.snapped(snap_vector)
			
				var new_pos := dragged_handle.transform.affine_inverse() * SVG.root_tag.world_to_canvas(event_pos)
				dragged_handle.set_pos(new_pos, true)
				was_handle_moved = false
			dragged_handle = null
		elif hovered_handle == null and event.is_pressed():
			should_deselect_all = true
		elif hovered_handle == null and event.is_released() and should_deselect_all:
			dragged_handle = null
			Indications.clear_all_selections()

func find_nearest_handle(event_pos: Vector2) -> Handle:
	var nearest_handle: Handle = null
	# Maximum grab distance is (9 / zoom).
	var nearest_dist_squared := 81 / (Indications.zoom * Indications.zoom)
	for handle in handles:
		var dist_to_handle_squared := event_pos.distance_squared_to(
					SVG.root_tag.canvas_to_world(handle.transform * handle.pos))
		if dist_to_handle_squared < nearest_dist_squared:
			nearest_dist_squared = dist_to_handle_squared
			nearest_handle = handle
	return nearest_handle

func move_selected_to_mouse() -> void:
	for handle in handles:
		if handle.tid == Indications.semi_selected_tid and handle is PathHandle and\
		handle.command_index == Indications.inner_selections[0]:
			if not get_viewport_rect().has_point(get_viewport().get_mouse_position()):
				return
			dragged_handle = handle
			# Move the handle that's being dragged.
			var mouse_position := get_global_mouse_position()
			
			var snap_size := absf(GlobalSettings.save_data.snap)
			if GlobalSettings.save_data.snap > 0.0:
				mouse_position = mouse_position.snapped(Vector2(snap_size, snap_size))
			
			var new_pos := dragged_handle.transform.affine_inverse() * SVG.root_tag.world_to_canvas(mouse_position)
			dragged_handle.set_pos(new_pos)
			was_handle_moved = true
			return
