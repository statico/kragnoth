class Map
  constructor: (@width, @height) ->
  get: (vec) ->
    return @map[vec[1]]?[vec[0]]
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
  set: (vec, value) ->
    @map[vec[1]] ?= {}
    @map[vec[1]][vec[0]] = value
    return value
  delete: (vec) ->
    if @map[vec[1]]?
      delete @map[vec[1]][vec[0]]
      delete @map[vec[1]] unless Object.keys(@map[vec[1]]).length
    return

class SparseMapList extends SparseMap
  constructor: (@width, @height) ->
    @map = {}
  add: (vec, value) ->
    list = @get(vec) ? []
    list.push value
    @set vec, list
  remove: (vec, value) ->
    list = @get(vec)
    if list?
      index = list.indexOf value
      if index != -1
        list.splice index, 1
      if list.length > 0
        @set vec, list
      else
        @delete vec
  isEmpty: (vec) ->
    return not @get(vec)?

class DenseMap extends Map
  constructor: (@width, @height) ->
    @map = new Array(@height)
    @map[i] = new Array(@width) for i in [0...@height]
  fill: (cb) ->
    vec = [0, 0]
    for y in [0...@height]
      for x in [0...@width]
        vec[0] = x
        vec[1] = y
        @set vec, cb()
    return
  set: (vec, value) ->
    @map[vec[1]] ?= new Array(@width)
    @map[vec[1]][vec[0]] = value
    return value
  delete: (vec) ->
    @map[vec[1]]?[vec[0]] = null
    return
  toString: ->
    ret = ''
    for y in [0...@height]
      for x in [0...@width]
        ret += @get [x, y]
      ret += '\n'
    return ret

exports.SparseMap = SparseMap
exports.SparseMapList = SparseMapList
exports.DenseMap = DenseMap
