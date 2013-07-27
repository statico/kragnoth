# Browser-side web client.

SockJS = require 'sockjs-client'

$ ->
  console.log 'XXX', SockJS
  window.SockJS = SockJS

  sock = new SockJS('http://localhost:8100/socket', undefined, debug: true)
  sock.onopen = ->
    console.log 'XXX', 'opened'
  sock.onmessage = (e) ->
    console.log 'XXX', 'message', e
  sock.onclose = ->
    console.log 'XXX', 'closed'

