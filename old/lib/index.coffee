shoe = require 'shoe'
dnode = require 'dnode'

exports.APPS = ['tilenames']

exports.tilenames = require './tilenames.coffee'

window?.runEntryPoint = (name) ->
  stream = shoe '/dnode'
  d = dnode()
  d.on 'remote', (remote) ->
    if name of exports
      exports[name](remote)
    else
      document.body.innerHTML = "No entry point named #{ name }"
  d.pipe(stream).pipe(d)
