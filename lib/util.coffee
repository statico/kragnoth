#!/usr/bin/env coffee

exports.requireEnv = (name, defaultValue) ->
  value = process.env[name]
  if not value?
    if defaultValue?
      value = defaultValue
    else
      console.error "Need to specify #{ name } env var"
      process.exit(1)
  return value
