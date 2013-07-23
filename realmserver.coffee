#!/usr/bin/env coffee

http = require 'http'
sockjs = require 'sockjs'

{Vec2} = require 'justmath'
{ServerWorld} = require './lib/world'
{Dummy} = require './lib/agents'

clients = {}
world = new ServerWorld(new Vec2(10, 10))
world.addAgent new Dummy()

socket = sockjs.createServer()
socket.on 'connection', (conn) ->
  console.log "Client #{ conn.id } connected"
  clients[conn.id] = conn
  conn.on 'close', ->
    console.log "Client #{ conn.id } disconnected"
    delete clients[conn.id]

update = ->
  state = world.simulate()
  for id, conn of clients
    conn.write JSON.stringify ['state', state]

setInterval update, 1000

server = http.createServer()
socket.installHandlers server, prefix: '/socket'
server.listen 9999, '0.0.0.0'
console.log "Realm Server listening."
