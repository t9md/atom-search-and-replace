{CompositeDisposable, Emitter, Point} = require 'atom'
path = require 'path'
Searcher = require './searcher'
Grammar = require atom.config.resourcePath + "/node_modules/first-mate/lib/grammar.js"
CSON = null
{
  getAdjacentPaneForPane
  smartScrollToBufferPosition
  decorateRange
} = require './utils'

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

  setGrammar: (editor, keyword) ->
    CSON ?= require 'season'
    atom.grammars.removeGrammarForScopeName('source.search-and-replace')
    grammarPath = path.join(__dirname, 'grammar', 'search-and-replace.cson')
    grammarObject = CSON.readFileSync(grammarPath) ? {}
    grammarObject.patterns[0].match = keyword
    grammar = atom.grammars.createGrammar(grammarPath, grammarObject)
    atom.grammars.addGrammar(grammar)
    editor.setGrammar(grammar)

  autoReveal: null
  isAutoReveal: -> @autoReveal

  observeCursorPositionChange: (editor) ->
    editor.onDidChangeCursorPosition ({oldBufferPosition, newBufferPosition}) =>
      return unless @isAutoReveal()
      if oldBufferPosition.row isnt newBufferPosition.row
        @jump(editor, reveal: true)

  registerCommands: (editor) ->
    editorElement = atom.views.getView(editor)
    editorElement.classList.add('search-and-replace')
    atom.commands.add editorElement,
      'search-and-replace:jump': => @jump(editor)
      'search-and-replace:reveal': => @jump(editor, reveal: true)
      'search-and-replace:toggle-auto-reveal': => @autoReveal = not @autoReveal

  jump: (editor, options={reveal: false}) ->
    isJumpableRow = (row) ->
      char = editor.getTextInBufferRange([[row, 0], [row, 1]])
      char.match(/\d/)?

    {row} = editor.getCursorBufferPosition()
    unless isJumpableRow(row)
      console.log 'skip'
      return
    [file, point] = @table[row]
    [row, column] = point.split(':')
    row = parseInt(row) - 1
    column = parseInt(column)
    point = new Point(row, column)
    originalPane = atom.workspace.getActivePane()
    pane = getAdjacentPaneForPane(atom.workspace.getActivePane())
    decorateOptions =
      class: 'search-and-replace-flash'
      timeout: 300
    pane.activate()
    atom.workspace.open(file).then (_editor) ->
      smartScrollToBufferPosition(_editor, point)
      range = _editor.bufferRangeForBufferRow(point.row)
      decorateRange(_editor, range, decorateOptions)

      if options.reveal
        originalPane.activate()
      else
        _editor.setCursorBufferPosition(point)

  observeNarrowChange: (editor) ->
    buffer = editor.getBuffer()
    buffer.onDidChange ({newRange}) ->
      return unless newRange.start.row is 0
      word = buffer.lineForRow(0)

  search: (word) ->
    @section = null
    @project = null

    subscriptions = new CompositeDisposable

    atom.workspace.open(null, {split: 'right'}).then (editor) =>
      editor.insertText("\n")
      editor.setCursorBufferPosition([0, 0])
      editor.isModified = -> false
      @registerCommands(editor)
      @setGrammar(editor, word)
      @observeNarrowChange(editor)

      subscriptions.add @searcher.onDidGetData (event) =>
        {data, cwd} = event
        if @project isnt event.project
          @project = event.project
          @insertAtLastRow(editor, "# #{@project}" + "\n")

        for line in data.split("\n")
          lastRow = editor.getLastBufferRow()
          text = @replaceLine(line, {lastRow, cwd})
          @insertAtLastRow(editor, text + "\n")

      subscriptions.add @searcher.onDidFinish (code) =>
        subscriptions.dispose()
        @observeCursorPositionChange(editor)

      for cwd in atom.project.getPaths()
        @section = null
        @project = path.basename(cwd)
        @searcher.search(word, {cwd, editor, @project})
