# Browser-side web client.

$ ->

  conn = new WebSocket('ws://localhost:8100', 'admin-protocol')
  conn.onerror = (err) -> console.log 'YYY', 'error', err
  conn.onclose = -> console.log 'YYY', 'close'
  conn.onmessage = (msg) -> console.log 'YYY', 'message', msg
