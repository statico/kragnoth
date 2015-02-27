keymaster = require 'keymaster'

{DenseMap} = require './map.coffee'

SIZE = 20
canvas = document.createElement 'canvas'
document.body.appendChild canvas
ctx = canvas.getContext '2d'
ctx.imageSmoothingEnabled = false
ctx.webkitImageSmoothingEnabled = false

info = document.createElement 'div'
document.body.appendChild info

gameSocket = view = null

cncSocket = new WebSocket('ws://127.0.0.1:8081', ['cnc'])
cncSocket.onopen = ->
  cncSocket.send JSON.stringify type: 'hello'
cncSocket.onmessage = (event) ->
  msg = JSON.parse event.data
  if msg.type is 'connect'
    gameSocket = new WebSocket(msg.url, ['game'])
    gameSocket.onmessage = (event) ->
      msg = JSON.parse event.data

      if msg.type is 'init'
        {width, height} = msg
        view = new DenseMap(width, height)
        view.fill -> {}
        canvas.width = width * SIZE
        canvas.height = height * SIZE

      if msg.type is 'diff'
        {tick, diff} = msg
        info.innerText = "Tick: #{ tick }\nPlayer: #{ msg.player.name }"

        for y, row of diff.map
          for x, obj of row
            state = view.get x, y
            state.tick = tick
            state.terrain = obj.terrain

        ctx.clearRect 0, 0, canvas.width, canvas.height
        for y, row of view.map
          for x, obj of row
            ctx.globalAlpha = if obj.tick is tick then 1.0 else 0.3
            style = switch obj.terrain
              when 0 then '#333'
              when 1 then '#999'
              when 2 then '#ccc'
              when 3 then '#806424'
            if style
              ctx.fillStyle = style
              ctx.fillRect x * SIZE, y * SIZE, SIZE, SIZE

        [x, y] = msg.player.pos
        ctx.fillStyle = '#DBA4D9'
        ctx.fillRect x * SIZE, y * SIZE, SIZE, SIZE

  return

sendInput = (dir) ->
  gameSocket?.send JSON.stringify type: 'input', direction: dir
for key, dir of {h: 'w', j: 's', k: 'n', l: 'e', y: 'nw', u: 'ne', b: 'sw', n: 'se'}
  do (key, dir) ->
    keymaster key, -> sendInput dir
