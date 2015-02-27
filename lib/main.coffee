#angular = require 'angular'
keymaster = require 'keymaster'

canvas = document.createElement 'canvas'
document.body.appendChild canvas
ctx = canvas.getContext '2d'
ctx.imageSmoothingEnabled = false
ctx.webkitImageSmoothingEnabled = false

info = document.createElement 'div'
document.body.appendChild info

gameSocket = null

cncSocket = new WebSocket('ws://127.0.0.1:8081', ['cnc'])
cncSocket.onopen = ->
  cncSocket.send JSON.stringify type: 'hello'
cncSocket.onmessage = (event) ->
  msg = JSON.parse event.data
  if msg.type is 'connect'
    gameSocket = new WebSocket(msg.url, ['game'])
    gameSocket.onmessage = (event) ->
      msg = JSON.parse event.data

      if msg.type is 'state'
        info.innerText = "Tick: #{ msg.tick }\nPlayer: #{ msg.state.player.name }"

        SIZE = 20
        terrain = msg.state.level.terrain
        w = terrain.width
        h = terrain.height
        canvas.width = w * SIZE
        canvas.height = h * SIZE
        for y in [0...h]
          for x in [0...w]
            switch terrain.map[y][x]
              when 0 then ctx.fillStyle = '#333'
              when 1 then ctx.fillStyle = '#999'
              when 2 then ctx.fillStyle = '#ccc'
              when 3 then ctx.fillStyle = '#806424'
              else ctx.fillStyle = '#0c0'
            ctx.fillRect x * SIZE, y * SIZE, SIZE, SIZE

        [x, y] = msg.state.player.pos
        ctx.fillStyle = '#DBA4D9'
        ctx.fillRect x * SIZE, y * SIZE, SIZE, SIZE

      else if msg.type is 'diff'
        info.innerText = "Tick: #{ msg.tick }\nPlayer: #{ msg.player.name }"

        SIZE = 20
        diff = msg.diff
        w = diff.width
        h = diff.height
        canvas.width = w * SIZE
        canvas.height = h * SIZE
        ctx.clearRect 0, 0, canvas.width, canvas.height
        for y, row of diff.map
          for x, obj of row
            switch obj.terrain
              when 0 then ctx.fillStyle = '#333'
              when 1 then ctx.fillStyle = '#999'
              when 2 then ctx.fillStyle = '#ccc'
              when 3 then ctx.fillStyle = '#806424'
              else ctx.fillStyle = '#0c0'
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
