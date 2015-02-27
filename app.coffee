#!./node_modules/.bin/coffee

express = require 'express'
browserify = require 'browserify-middleware'
websocket = require 'websocket'
http = require 'http'
{vec2} = require 'gl-matrix'

# TODO: Inject
WEB_PORT = 8080
CNC_PORT = 8081
GAME_PORT = 8082

app = express()

app.get '/main.js', browserify('./lib/main.coffee', transform: ['coffeeify'])

app.get '/', (req, res) ->
  res.send '''
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8"/>
        <title>Kragnoth</title>
        <style>
        body {
          background: black;
          color: white;
          font-family: sans-serif;
        }
        </style>
      </head>
      <body>
        <script src="/main.js"></script>
      </body>
    </html>
    '''

app.listen WEB_PORT, ->
  console.log "Web server listening on http://127.0.0.1:#{ WEB_PORT }/"

cncServer = http.createServer()
cncServer.listen CNC_PORT, -> console.log "CNC server on #{ CNC_PORT }"

cncWSServer = new websocket.server(httpServer: cncServer)
cncWSServer.on 'request', (req) ->
  conn = req.accept 'cnc', req.origin
  console.log 'Accepted CNC connection'
  conn.on 'message', (event) ->
    msg = JSON.parse if event.type is 'utf8' then event.utf8Data else event.binaryData
    console.log 'XXX', 'CNC message', msg
  conn.on 'close', ->
    console.log 'XXX', 'CNC closed'
  conn.on 'error', (err) ->
    console.log 'XXX', 'CNC error', err
  conn.sendUTF JSON.stringify type: 'hello'
  conn.sendUTF JSON.stringify type: 'connect', url: "ws://127.0.0.1:#{ GAME_PORT }/"

gameServer = http.createServer()
gameServer.listen GAME_PORT, -> console.log "Game server on #{ GAME_PORT }"

gameWSServer = new websocket.server(httpServer: gameServer)
gameWSServer.on 'request', (req) ->
  conn = req.accept 'game', req.origin
  console.log 'Accepted Game connection'
  conn.on 'message', (event) ->
    msg = JSON.parse if event.type is 'utf8' then event.utf8Data else event.binaryData
    console.log 'XXX', 'Game message', msg
  conn.on 'error', (err) ->
    console.log 'XXX', 'Game error', err

  world = new World('player1')
  scheduler = new Scheduler(world, conn)
  scheduler.start()
  conn.on 'close', ->
    scheduler.end()

class Scheduler
  constructor: (@world, @playerConn) ->
    @tickSpeed = 100
    @tick = 0
    @nextInput = null
    @playerConn.on 'message', (event) =>
      msg = JSON.parse if event.type is 'utf8' then event.utf8Data else event.binaryData
      if msg.type is 'input'
        @nextInput = msg.direction
  send: (obj) -> @playerConn.sendUTF JSON.stringify obj
  start: ->
    doTick = =>
      start = Date.now()
      @tick++
      @world.simulate(direction: @nextInput)
      @nextInput = null
      @send
        type: 'state'
        tick: @tick
        state: @world.toJSON()
      next = (start + @tickSpeed) - Date.now()
      @timer = setTimeout doTick, if next < 0 then 0 else next
    doTick()
  end: ->
    clearTimeout @timer

class World
  constructor: (playerName) ->
    @level = new Level()
    @player = new Player(playerName)
  simulate: (input) ->
    delta = switch input.direction
      when 'n' then [0, -1]
      when 's' then [0, 1]
      when 'e' then [1, 0]
      when 'w' then [-1, 0]
      else [0, 0]
    vec2.add @player.pos, @player.pos, delta
    vec2.min @player.pos, @player.pos, [@level.width - 1, @level.height - 1]
    vec2.max @player.pos, @player.pos, [0, 0]

  toJSON: ->
    return {
      player: @player.toJSON()
      level: @level.toJSON()
    }

class Level
  constructor: ->
    @name = null
    @width = 40
    @height = 14
    @terrain = DenseMap.fromJSON
      width: @width
      height: @height
      map: [
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,3,3,3,3,3,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,3,3,0,0,0,1,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,0,0,0,0,1,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,1,1,1,3,1,1,1,1,1,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,1,1,1,1,1,1,1,3,1,1,1,1,1,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,1,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,1,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0]
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ]
  toJSON: ->
    return {
      name: @name
      width: @width
      height: @height
      terrain: @terrain.toJSON()
    }

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
  set: (x, y, value) ->
    @map[y] ?= new Array(@width)
    @map[y][x] = value
    return value
  delete: (x, y) ->
    @map[y]?[x] = null
    return

class Player
  constructor: (@name) ->
    @pos = [0, 0]
  toJSON: ->
    return {
      name: @name
      pos: @pos
    }
