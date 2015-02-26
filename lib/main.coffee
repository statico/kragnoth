document.body.innerHTML += 'hello<br/>'

cncSocket = new WebSocket('ws://127.0.0.1:8081', ['cnc'])
cncSocket.onopen = ->
  cncSocket.send JSON.stringify type: 'hello'
cncSocket.onmessage = (event) ->
  document.body.innerHTML += "message: #{ event.data }<br/>"
