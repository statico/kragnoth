fs = require 'fs'

datadir = "#{ __dirname }/../public/data"

TILEDATA = "#{ datadir }/tiles.json"

exports.getTileName = (location, cb) ->
  [x, y] = location
  fs.readFile TILEDATA, 'utf8', (err, data) ->
    obj = JSON.parse data
    if obj.names?[x]?[y]?
      cb? obj.names?[x][y]
    else
      cb? null

exports.setTileName = (location, name, cb) ->
  [x, y] = location
  fs.readFile TILEDATA, 'utf8', (err, data) ->
    obj = JSON.parse data
    if not obj.names?[x]?[y]?
      obj.names ?= {}
      obj.names[x] ?= {}
    obj.names[x][y] = name
    fs.writeFile TILEDATA, JSON.stringify(obj), 'utf8', ->
      cb? null
