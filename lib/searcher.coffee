{BufferedProcess} = require 'atom'


module.exports =
class Searcher
  constructor: ->

  search: (text, {cwd, onData, onFinish}) ->
    command = 'ag'
    args = ['--nocolor', '--column', text]
    options = {cwd: cwd, env: process.env}
    @runCommand {command, args, options, onData, onFinish}

  runCommand: ({command, args, options, onData, onFinish}) ->
    cwd = options.cwd

    stdout = (output) -> onData({data: output, cwd})
    stderr = (output) -> onData({data: output, cwd})
    exit = (code) -> onFinish(code)

    process = new BufferedProcess {command, args, options, stdout, stderr, exit}
    process.onWillThrowError ({error, handle}) ->
      if error.code is 'ENOENT' and error.syscall.indexOf('spawn') is 0
        console.log "ERROR"
      handle()
    process
