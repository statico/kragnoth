class Map
  constructor: (@width, @height) ->
  get: (x, y) ->
    return @map[y]?[x]
  toJSON: ->
    return {
      width: @width
      height: @height
      map: @map
    }
  @fromJSON: (obj) ->
    map = new this
    map.map = obj.map
    map.width = obj.width
    map.height = obj.height
    return map

class SparseMap extends Map
  constructor: (@width, @height) ->
    @map = {}
  set: (x, y, value) ->
    @map[y] ?= {}
    @map[y][x] = value
    return value
  delete: (x, y) ->
    if @map[y]?
      delete @map[y][x]
      delete @map[y] unless Objects.keys(@map[y]).length
    return

class DenseMap extends Map
  constructor: (@width, @height) ->
    @map = new Array(@height)
    @map[i] = new Array(@width) for i in [0...@height]
  fill: (cb) ->
    for y in [0...@height]
      for x in [0...@width]
        @set x, y, cb()
    return
  set: (x, y, value) ->
    @map[y] ?= new Array(@width)
    @map[y][x] = value
    return value
  delete: (x, y) ->
    @map[y]?[x] = null
    return

exports.SparseMap = SparseMap
exports.DenseMap = DenseMap
