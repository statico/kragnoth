# Browser-side web client.

conn = null

tryConnectingToAdmin = ->
  url = 'ws://localhost:8100'
  console.log "Connecting to #{ url }..."
  conn = new WebSocket(url, 'admin-protocol')

  conn.onerror = (err) ->
    console.error "Admin WebSocket error:", err

  conn.onopen = ->
    conn.send JSON.stringify ['auth', {}] # Dumb for now.

  conn.onclose = ->
    console.log "Admin WebSocket closed. Reconnecting."
    setTimeout tryConnectingToAdmin, 1000

  conn.onmessage = (message) ->
    try
      tuple = JSON.parse message.data
    catch e
      console.error "Error parsing admin message:", message.data
      return
    [command, obj] = tuple
    switch command
      when 'connect-to-realm'
        tryConnectingToRealm obj.url
      else
        console.error "Unknown admin command: #{ command }"
    return

rconn = null

tryConnectingToRealm = (url) ->
  console.log "Connecting to realm #{ url }..."
  rconn = new WebSocket(url, 'realm-protocol')

  rconn.onerror = (err) ->
    console.error "Realm WebSocket error:", err

  rconn.onopen = ->
    console.log "Realm WebSocket opened"

  rconn.onclose = ->
    console.log "Realm WebSocket closed. Reconnecting."
    setTimeout (-> tryConnectingToRealm url), 1000

  rconn.onmessage = (msg) ->
    console.log 'XXX Got state'

$ ->
  tryConnectingToAdmin()
