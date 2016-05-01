{CompositeDisposable, Emitter, Point} = require 'atom'
path = require 'path'
Searcher = require './searcher'
{getAdjacentPaneForPane, smartScrollToBufferPosition} = require './utils'

module.exports =
  activate: ->
    @subscriptions = new CompositeDisposable
    @searcher ?= new Searcher

  deactivate: ->
    @subscriptions.dispose()
    {@subscriptions, @emitter} = {}

  subscribe: (args...) ->
    @subscriptions.add args...

  provideSearchAndReplace: ->
    search: @search.bind(this)

  insertAtLastRow: (editor, text) ->
    lastRow = editor.getLastBufferRow()
    range = editor.bufferRangeForBufferRow(lastRow)
    editor.setTextInBufferRange(range, text)

  saveTable: (row, file, point) ->
    @table ?= {}
    @table[row] = [file, point]

  replaceLine: (line, {lastRow, cwd}) ->
    line.replace /^(.*?):(\d+:\d+):(.*)/, (str, file, pos, line) =>
      lineText = "#{pos}:#{line}"
      filePath = path.join(cwd, file)
      text = if @section is file
        @saveTable(lastRow, filePath, pos)
        lineText
      else
        @section = file
        @saveTable(lastRow+1, filePath, pos)
        '## ' + @section + "\n" + lineText

  setGrammar: (editor) ->
    editor.setGrammar(atom.grammars.grammarForScopeName('source.gfm'))

  registerCommands: (editor) ->
    editorElement = atom.views.getView(editor)
    editorElement.classList.add('search-and-replace')
    atom.commands.add editorElement,
      'search-and-replace:jump': => @jump(editor)
      'search-and-replace:reveal': => @jump(editor, reveal: true)

  jump: (editor, options={reveal: false}) ->
    {row} = editor.getCursorBufferPosition()
    [file, point] = @table[row]
    [row, column] = point.split(':')
    row = parseInt(row) - 1
    column = parseInt(column)
    point = new Point(row, column)
    originalPane = atom.workspace.getActivePane()
    pane = getAdjacentPaneForPane(atom.workspace.getActivePane())
    pane.activate()
    atom.workspace.open(file).then (_editor) ->
      smartScrollToBufferPosition(_editor, point)
      if options.reveal
        originalPane.activate()
      else
        _editor.setCursorBufferPosition(point)

  search: (word) ->
    @section = null
    @project = null

    subscriptions = new CompositeDisposable

    atom.workspace.open(null, {split: 'right'}).then (editor) =>
      @setGrammar(editor)
      @registerCommands(editor)
      editor.insertText("[search results]\n\n")
      editor.setCursorBufferPosition([0, 0])

      subscriptions.add @searcher.onDidGetData (event) =>
        {data, cwd} = event
        if @project isnt event.project
          @project = event.project
          @insertAtLastRow(editor, "# #{@project}" + "\n")

        for line in data.split("\n")
          lastRow = editor.getLastBufferRow()
          text = @replaceLine(line, {lastRow, cwd})
          @insertAtLastRow(editor, text + "\n")

      subscriptions.add @searcher.onDidFinish (code) ->
        subscriptions.dispose()

      for cwd in atom.project.getPaths()
        @section = null
        @project = path.basename(cwd)
        @searcher.search(word, {cwd, editor, @project})
