#!/usr/bin/env coffee

sjsc = require 'sockjs-client'

{ClientWorld} = require './lib/game'

class View

  constructor: ->
    @charm = require('charm')()
    @charm.pipe(process.stdout)
    @charm
      .reset()
      .erase('screen')
      .cursor(false)
      .position(0, 0)

  draw: (world) ->
    @charm.erase 'screen'
    for agent in world.getAgents()
      @charm.position agent.location.x, agent.location.y
      @charm.write '@'

  teardown: ->
    @charm.cursor(true).erase('line')

client = null
world = new ClientWorld()
view = new View()

process.on 'exit', ->
  view.teardown()

tryConnecting = ->

  client = sjsc.create 'http://localhost:9999/socket'

  client.on 'connection', ->

  client.on 'data', (raw) ->
    message = JSON.parse raw
    return if not message?.length == 2
    [cmd, data] = message
    return if cmd != 'state'
    world.loadFromState data
    view.draw world

  client.on 'error', (err) ->
    client.close()
    if err[0]?.code in ['ECONNREFUSED', 'ECONNRESET']
      setTimeout tryConnecting, 500
    else
      console.log err

tryConnecting()
