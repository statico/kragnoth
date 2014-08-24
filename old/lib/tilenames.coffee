TILEFILE = 'kins32.png'
TILEDATA = 'tiles.json'
TW = 32
TH = 32

module.exports = (remote) ->

  $img = $('<img>').attr(src: "/data/#{ TILEFILE }")
  img = $img[0]

  $canvas = $('<canvas>')
  canvas = $canvas[0]
  canvas.style.float = 'left'
  ctx = canvas.getContext '2d'

  location = $('<div>')
  input = $('<input type="text">')

  $(document.body).append canvas, location, input

  selected = null

  clear = ->
    ctx.fillStyle = '#ccc'
    ctx.fillRect 0, 0, canvas.width, canvas.height
    ctx.drawImage img, 0, 0
    if selected
      ctx.fillStyle = 'transparent'
      ctx.strokeStyle = 'cyan'
      ctx.lineWidth = 4
      ctx.strokeRect selected[0] * TW, selected[1] * TH, TW, TH

  drawCursor = (mx, my) ->
    clear()
    tx = Math.floor(mx / TW)
    ty = Math.floor(my / TH)
    ctx.fillStyle = 'transparent'
    ctx.strokeStyle = 'black'
    ctx.lineWidth = 2
    ctx.strokeRect tx * TW, ty * TH, TW, TH
    return [tx, ty]

  $img.on 'load', ->
    canvas.width = img.width
    canvas.height = img.height

    $canvas.on 'mousemove', (e) ->
      drawCursor e.offsetX, e.offsetY

    $canvas.on 'mousedown', (e) ->
      selected = drawCursor e.offsetX, e.offsetY
      clear()
      location.text JSON.stringify selected
      setTimeout((-> input.focus()), 0)
      remote.getTileName selected, (name) ->
        input.val name

    input.on 'keyup', ->
      remote.setTileName selected, input.val()

    clear()
