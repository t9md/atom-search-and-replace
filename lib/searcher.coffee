{BufferedProcess, Emitter} = require 'atom'


module.exports =
class Searcher
  constructor: ->
    @emitter = new Emitter

  onDidGetData: (fn) ->
    @emitter.on 'did-get-data', fn

  onDidFinish: (fn) ->
    @emitter.on 'did-finish', fn

  search: (text, {cwd, editor, project}) ->
    command = 'ag'
    args = ['--nocolor', '--column', text]
    options = {cwd: cwd, env: process.env}
    @runCommand {command, args, editor, options, project}

  runCommand: ({command, args, options, editor, project}) ->
    cwd = options.cwd
    onData = (data) => @emitter.emit('did-get-data', {data, project, cwd})
    onFinish = (code) => @emitter.emit('did-finish', code)

    stdout = (output) -> onData(output)
    stderr = (output) -> onData(output)
    exit = (code) -> onFinish(code)
    process = new BufferedProcess {command, args, options, stdout, stderr, exit}
    process.onWillThrowError ({error, handle}) ->
      if error.code is 'ENOENT' and error.syscall.indexOf('spawn') is 0
        console.log "ERROR"
      handle()
