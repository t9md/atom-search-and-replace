{CompositeDisposable, Emitter} = require 'atom'
Searcher = require './searcher'

module.exports =
  activate: ->
    @subscriptions = new CompositeDisposable
    @searcher ?= new Searcher
    @subscribe atom.commands.add 'atom-text-editor',
      'search-and-replace:start': =>
        @searchAndReplace()

  deactivate: ->
    @subscriptions.dispose()
    {@subscriptions, @emitter} = {}

  subscribe: (args...) ->
    @subscriptions.add args...

  searchAndReplace: ->
    subscriptions = new CompositeDisposable
    atom.workspace.open(null, {split: 'right'}).then (editor) =>
      editor.insertText("[search results]\n\n")
      editor.setCursorBufferPosition([0, 0])
      section = null
      subscriptions.add @searcher.onDidGetData (data) ->
        for line in data.split("\n")
          text = line.replace /^(.*?):(\d+:\d+):(.*)/, (str, file, pos, line) ->
            if section is file
              line
            else
              section = file
              '### ' + section + "\n" + line
          lastRow = editor.getLastBufferRow()
          range = editor.bufferRangeForBufferRow(lastRow)
          editor.setTextInBufferRange(range, text + "\n")
          # editor.insertText(text + "\n")
      subscriptions.add @searcher.onDidFinish (code) -> subscriptions.dispose()

      for cwd in atom.project.getPaths()
        @searcher.search('editor', {cwd, editor})
