#!/usr/bin/env coffee

sjsc = require 'sockjs-client'

{Map} = require './lib/map'
{ClientWorld} = require './lib/game'

class View

  @Colors: ['red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']

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

    # Draw a character for each agent.
    @charm.foreground('black')
    world.map.foreach (p) =>
      @charm.position p.x + 1, p.y + 1
      switch world.map.get(p)
        when Map.Cells.EMPTY
          @charm.write ' '
        when Map.Cells.WALL
          switch world.map.wallType p
            when 'h' then @charm.write '-'
            when 'v' then @charm.write '|'
            else @charm.write '+'
        when Map.Cells.ROOM
          @charm.write '.'
        when Map.Cells.DOOR
          @charm.write '_'
        when Map.Cells.HALLWAY
          @charm.write '#'

    # Always draw alive agents on top of dead ones.
    world.agents.sort (a, b) -> if a.isAlive() then 1 else -1

    # Draw a character for each agent.
    for agent in world.agents
      @charm.position agent.location.x + 1, agent.location.y + 1

      # All dead agents are a corpse.
      if not agent.isAlive()
        @charm.foreground('black').write 'x'
        continue

      switch agent.type
        when 'drone' then @charm.foreground('white').write 'o'
        when 'mosquito' then @charm.foreground('red').write 'M'
        else @charm.write '?'

    return

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
