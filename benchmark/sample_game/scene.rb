# Uses the attr_gtk macro to reach the args tree from a class.
class Scene
  attr_gtk

  def tick
    state.scene ||= :title

    case state.scene
    when :title then tick_title
    when :play then tick_play
    end
  end

  def tick_title
    state.scene = :play if inputs.keyboard.key_down.space

    outputs.labels << {x: 640, y: 360, text: "DragonRuby", alignment_enum: 1}
  end

  def tick_play
    outputs.primitives << {x: 0, y: 0, w: grid.w, h: grid.h, path: :solid}
    outputs.labels << {x: grid.w / 2, y: grid.h - 40, text: "Playing", alignment_enum: 1}
    geometry.angle_to({x: 0, y: 0}, inputs.mouse)
  end
end
