fs = require 'fs'

# Some sane defaults.
module.exports =
  COOKIE_SECRET: 'sekrit-cookiez'
  SESSION_SECRET: 'sekret-sezzunz'

# Override constants in a secrets.json file, which isn't checked in.
secretsFile = "#{ __dirname }/../secrets.json"
if fs.existsSync secretsFile
  obj = JSON.parse fs.readFileSync(secretsFile, 'utf8')
  for key, value of obj
    module.exports[key] = value

# Override constants using env vars.
for key, value of module.exports
  if key of process.env
    module.exports[key] = process.env[key]
