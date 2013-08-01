{print} = require 'util'
{spawn} = require 'child_process'

task 'server', 'Watch src/ for changes and serve', ->
  coffee = spawn 'coffee', ['-w', '-c', '-o', 'lib', 'src']
  server = spawn 'http-server'
  
  for p in [coffee, server]
    p.stderr.on 'data', (data) ->
      process.stderr.write data.toString()
    p.stdout.on 'data', (data) ->
      print data.toString()