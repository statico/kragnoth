#!/usr/bin/env coffee

http = require 'http'
sockjs = require 'sockjs'

{Vec2} = require 'justmath'
{GameMaster} = require './lib/game'

clients = {}
gm = new GameMaster()

socket = sockjs.createServer()
socket.on 'connection', (conn) ->
  console.log "Client #{ conn.id } connected"
  clients[conn.id] = conn
  conn.on 'close', ->
    console.log "Client #{ conn.id } disconnected"
    delete clients[conn.id]

update = ->
  gm.doRound()
  state = gm.getFullState()
  for id, conn of clients
    conn.write JSON.stringify ['state', state]

setInterval update, 1000

server = http.createServer()
socket.installHandlers server, prefix: '/socket'
server.listen 9999, '0.0.0.0'
console.log "Realm Server listening."
