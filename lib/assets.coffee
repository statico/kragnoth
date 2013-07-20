#!/usr/bin/env coffee

module.exports = (assets) ->
  assets.root = "#{ __dirname }/../public"
  assets.addJs 'third-party/jquery/jquery.js'
