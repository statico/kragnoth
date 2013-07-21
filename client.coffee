#!/usr/bin/env coffee

sjsc = require 'sockjs-client'
charm = require('charm')()

client = null

charm.pipe process.stdout
charm.reset()

process.on 'exit', ->
  charm.cursor true
  charm.erase 'line'

tryConnecting = ->

  client = sjsc.create 'http://localhost:9999/socket'

  client.on 'connection', ->
    charm.erase 'screen'
    charm.cursor false
    charm.position 0, 0

  client.on 'data', (raw) ->
    message = JSON.parse raw
    return if not message?.length == 2
    [cmd, data] = message
    return if cmd != 'fullstate'

    charm.erase 'screen'
    for id, state of data
      charm.position state.x, state.y
      charm.write '@'

  client.on 'error', (err) ->
    client.close()
    if err[0]?.code in ['ECONNREFUSED', 'ECONNRESET']
      setTimeout tryConnecting, 500
    else
      console.log err

tryConnecting()
