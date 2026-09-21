#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/mermaid_term"

scene = MermaidTerm::Scene
light = scene::LIGHT
heavy = scene::Stroke.new(weight: :heavy, pattern: :solid)
dotted = scene::Stroke.new(weight: :light, pattern: :dotted)
items = []
[[1, 1, "開始", :rounded], [28, 1, "判断", :sharp], [15, 12, "完了", :sharp]].each do |x, y, label, corners|
  items << scene::Box.new(rect: scene::Rect.new(x: x, y: y, width: 12, height: 3), stroke: light,
                          corners: corners, role: :node_border, layer: :node)
  items << scene::Text.new(x: x + 2, y: y + 1, string: label, role: :node_text, layer: :label, emphasis: nil)
end
items << scene::Polyline.new(points: [[12, 2], [28, 2]], stroke: dotted, role: :edge, layer: :edge)
items << scene::Marker.new(x: 28, y: 2, kind: :cross, direction: :e, role: :marker, layer: :marker)
items << scene::Polyline.new(points: [[7, 3], [7, 7], [20, 7], [20, 12]], stroke: light, role: :edge, layer: :edge)
items << scene::Marker.new(x: 20, y: 12, kind: :arrow, direction: :s, role: :marker, layer: :marker)
items << scene::Polyline.new(points: [[34, 3], [34, 9], [22, 9], [22, 12]], stroke: heavy, role: :edge, layer: :edge)
items << scene::Marker.new(x: 22, y: 12, kind: :circle, direction: :s, role: :marker, layer: :marker)

picture = scene.new(width: 42, height: 16, items: items)
charset = ARGV.include?("--ascii") ? :ascii : :unicode
puts MermaidTerm::Output.render(MermaidTerm::Raster.rasterize(picture, charset: charset), charset: charset)
