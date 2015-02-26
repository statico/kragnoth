#!./node_modules/.bin/coffee

express = require 'express'
browserify = require 'browserify-middleware'

app = express()

app.get '/main.js', browserify('./lib/main.coffee', transform: ['coffeeify'])

app.get '/', (req, res) ->
  res.send 200, '''
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8"/>
        <title>Kragnoth</title>
      </head>
      <body>
        <script src="/main.js"></script>
      </body>
    </html>
    '''

app.listen 8080, ->
  console.log "Listening on http://127.0.0.1:8080/"
