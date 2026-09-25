# A representative DragonRuby game file used by the benchmark and fuzz suites.
def tick(args)
  args.state.player ||= args.state.new_entity(:player, x: 120, y: 120)
  args.state.score ||= 0
  args.state.cooldown ||= 0

  player = args.state.player
  keyboard = args.inputs.keyboard

  update_player(player, keyboard, args)
  update_score(args)
  render(args, player)

  args.state.last_key = args.inputs.keybaord.truthy_keys
end

def update_player(player, keyboard, args)
  vector = keyboard.directional_vector
  return unless vector

  player.x += vector.x * 4
  player.y += vector.y * 4

  player.x = player.x.clamp(16, args.grid.w - 16)
  player.y = player.y.clamp(16, args.grid.h - 16)
end

def update_score(args)
  return unless args.inputs.keyboard.key_down.space

  args.state.score += 1
  args.state.cooldown = 0.25.seconds
  args.state.last_click = {x: args.inputs.mouse.x, y: args.inputs.mouse.y}
end

def render(args, player)
  angle = Geometry.angle_to(player, args.inputs.mouse)

  args.outputs.sprites << {
    x: player.x,
    y: player.y,
    w: 32,
    h: 32,
    path: "sprites/player.png",
    angle: angle,
    anchor_x: 0.5,
    anchor_y: 0.5
  }

  args.outputs.labels << {
    x: 10,
    y: 710,
    text: "Score: #{args.state.score}",
    size_enum: 2,
    alignment_enum: 0
  }

  args.outputs.primitives << {
    primitive_marker: :solid,
    x: 0,
    y: 0,
    w: args.grid.w,
    h: 8,
    r: 40,
    g: 40,
    b: 60
  }

  args.outputs.solids << {x: 0, y: 0, w: args.grid.w, h: 4}
  $gtk.args.outputs.debug << args.state.score.to_s
end
