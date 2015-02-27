#!./node_modules/.bin/coffee

ROT = require 'rot.js'
express = require 'express'
browserify = require 'browserify-middleware'
websocket = require 'websocket'
http = require 'http'
{vec2} = require 'gl-matrix'

{SparseMap, DenseMap} = require './lib/map'

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

app.listen WEB_PORT, '0.0.0.0', ->
  console.log "Web server listening on http://127.0.0.1:#{ WEB_PORT }/"

cncServer = http.createServer()
cncServer.listen CNC_PORT, '0.0.0.0', -> console.log "CNC server on #{ CNC_PORT }"

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
gameServer.listen GAME_PORT, '0.0.0.0', -> console.log "Game server on #{ GAME_PORT }"

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
    @playerConn.on 'message', (event) =>
      msg = JSON.parse if event.type is 'utf8' then event.utf8Data else event.binaryData
      if msg.type is 'input'
        @world.player.lastInput = msg
    @send type: 'init', width: @world.level.width, height: @world.level.height
  send: (obj) -> @playerConn.sendUTF JSON.stringify obj
  start: ->
    doTick = =>
      start = Date.now()
      @tick++
      diff = @world.simulate(@tickSpeed, @tick)
      monsters = []
      for monster in @world.monsters
        [x, y] = monster.pos
        monsters.push monster.toViewJSON() if diff.get x, y
      @send
        type: 'tick'
        tick: @tick
        player: @world.player.toJSON()
        monsters: monsters
        diff: diff.toJSON()
        messages: @world.messages
      next = (start + @tickSpeed) - Date.now()
      @timer = setTimeout doTick, if next < 0 then 0 else next
    doTick()
  end: ->
    clearTimeout @timer

class World
  constructor: (playerName) ->
    @level = new Level()
    @player = new Player(playerName)
    @monsters = [new Mosquito(), new Slug()]
    @messages = null

    for actor in [@player].concat @monsters
      [x, y] = actor.pos
      @level.actors.set x, y, actor

  simulate: (tickSpeed, tick) ->
    @messages = []

    updatePos = (pos, dir) =>
      delta = switch dir
        when 'n' then [0, -1]
        when 's' then [0, 1]
        when 'e' then [1, 0]
        when 'w' then [-1, 0]
        when 'nw' then [-1, -1]
        when 'sw' then [-1, 1]
        when 'ne' then [1, -1]
        when 'se' then [1, 1]
        else [0, 0]
      next = [0, 0]
      vec2.add next, pos, delta
      vec2.min next, next, [@level.width - 1, @level.height - 1]
      vec2.max next, next, [0, 0]
      tile = @level.terrain.get next[0], next[1]
      actor = @level.actors.get next[0], next[1]
      if tile in [2, 3] and not actor
        vec2.copy pos, next
        return true
      else
        return false

    command = @player.simulate()
    if command?.command is 'move'
      oldPos = vec2.copy [0,0], @player.pos
      if updatePos @player.pos, command.direction
        @level.actors.delete oldPos[0], oldPos[1]
        @level.actors.set @player.pos[0], @player.pos[1], @player

    for monster in @monsters
      monster.lastTick ?= tick
      delta = (tick - monster.lastTick) * tickSpeed
      continue unless delta >= 1000 / monster.speed
      command = monster.simulate()
      if command?.command is 'move'
        oldPos = vec2.copy [0,0], monster.pos
        if updatePos monster.pos, command.direction
          @level.actors.delete oldPos[0], oldPos[1]
          @level.actors.set monster.pos[0], monster.pos[1], monster
      monster.lastTick = tick

    console.log 'XXX', @level.actors

    # computer what areas the player can see
    diff = new SparseMap(@level.width, @level.height)
    test = (x, y) => @level.terrain.get(x, y) in [2, 3]
    fov = new ROT.FOV.PreciseShadowcasting(test)
    [x, y] = @player.pos
    fov.compute x, y, 10, (x, y, _, visible) =>
      # for now, just send terrain data
      diff.set x, y, terrain: @level.terrain.get x, y

    return diff

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
    @actors = new SparseMap(@width, @height)
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
        [0,1,2,2,2,1,2,2,2,2,1,1,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,1,1,2,2,2,2,2,1,0,0,0,0,0,1,1,1,1,1,1,1,3,1,1,1,1,1,1,0,0,0]
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

class Player
  constructor: (@name) ->
    @pos = [3, 3]
    @lastInput = null
  simulate: ->
    if @lastInput
      command = { command: 'move', direction: @lastInput.direction }
      @lastInput = null
    return command
  toJSON: ->
    return {
      name: @name
      pos: @pos
    }

class Monster
  simulate: ->
    directions = 'n w s e nw sw se ne'.split ' '
    dir = directions[Math.floor(Math.random() * directions.length)]
    return { command: 'move', direction: dir }
  toJSON: ->
    return {
      name: @name
      pos: @pos
      speed: @speed
    }
  toViewJSON: ->
    return {
      name: @name
      pos: @pos
    }

class Mosquito extends Monster
  constructor: ->
    @name = 'mosquito'
    @pos = [10, 10]
    @speed = 10

class Slug extends Monster
  constructor: ->
    @name = 'slug'
    @pos = [11, 10]
    @speed = 1
