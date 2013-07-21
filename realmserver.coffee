#!/usr/bin/env coffee

http = require 'http'
sockjs = require 'sockjs'

clients = {}

socket = sockjs.createServer()
socket.on 'connection', (conn) ->
  console.log "Client #{ conn.id } connected"
  clients[conn.id] = conn
  conn.on 'close', ->
    console.log "Client #{ conn.id } disconnected"
    delete clients[conn.id]

update = ->
  r = -> Math.floor(Math.random() * 10)
  message = ['fullstate', {1: {x: r(), y: r()}}]
  for id, conn of clients
    conn.write JSON.stringify message

setInterval update, 1000

server = http.createServer()
socket.installHandlers server, prefix: '/socket'
server.listen 9999, '0.0.0.0'
console.log "Realm Server listening."
