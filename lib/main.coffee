{CompositeDisposable, Emitter, Point} = require 'atom'
path = require 'path'
_ = require 'underscore-plus'
Searcher = require './searcher'
Grammar = require atom.config.resourcePath + "/node_modules/first-mate/lib/grammar.js"
CSON = null
{
  getAdjacentPaneForPane
  smartScrollToBufferPosition
  decorateRange
  openInAdjacentPane
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

  saveTable: (row, filePath, point) ->
    @table ?= {}
    @table[row] = [filePath, point]

  readGrammarFile: (grammarPath) ->
    CSON ?= require 'season'
    CSON.readFileSync(grammarPath) ? {}

  updateGrammar: (editor, keyword) ->
    grammarPath = path.join(__dirname, 'grammar', 'search-and-replace.cson')
    @keywordGrammarObject ?= @readGrammarFile(grammarPath)
    atom.grammars.removeGrammarForScopeName('source.search-and-replace')
    @keywordGrammarObject.patterns[0].match = "(?i:#{_.escapeRegExp(keyword)})"
    grammar = atom.grammars.createGrammar(grammarPath, @keywordGrammarObject)
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
    {row} = editor.getCursorBufferPosition()
    return unless entry = @table[row]

    [filePath, point] = entry
    point = new Point(parseInt(point[0]) - 1, parseInt(point[1]))

    highlightRow = (editor, row) ->
      range = editor.bufferRangeForBufferRow(point.row)
      decorateRange editor, range,
        class: 'search-and-replace-flash'
        timeout: 300

    originalPane = atom.workspace.getActivePane()
    openInAdjacentPane(filePath).then (_editor) ->
      smartScrollToBufferPosition(_editor, point)
      highlightRow(_editor, point.row)

      if options.reveal
        originalPane.activate()
      else
        _editor.setCursorBufferPosition(point)

  observeNarrowInputChange: (editor) ->
    buffer = editor.getBuffer()
    buffer.onDidChange ({newRange}) ->
      return unless newRange.start.row is 0
      word = buffer.lineForRow(0)
      console.log word

  parseLine: (line) ->
    m = line.match(/^(.*?):(\d+):(\d+):(.*)$/)
    if m?
      {
        filePath: m[1]
        row: m[2]
        column: m[3]
        lineText: m[4]
      }
    else
      console.log 'nmatch!', line
      {}

  formatLine: (lineParsed, cwd) ->
    {filePath, row, column, lineText} = lineParsed
    "#{row}:#{column}:#{lineText}"

  outputterForProject: (project, editor) ->
    initialData = true
    (event) =>
      {data} = event
      if initialData
        @insertAtLastRow(editor, "# #{path.basename(project)}\n")
        initialData = false

      currentFile = null
      for line in data.split("\n") when line.length
        lineParsed = @parseLine(line)
        {filePath, row, column} = lineParsed
        if filePath isnt currentFile
          currentFile = filePath
          @insertAtLastRow(editor, "## #{currentFile}\n")
        range = @insertAtLastRow(editor, @formatLine(lineParsed) + "\n")
        @saveTable(range.start.row, path.join(project, filePath), [row, column])

  search: (word) ->
    openInAdjacentPane(null).then (editor) =>
      editor.insertText("#{word}\n")
      editor.setCursorBufferPosition([0, Infinity])
      editor.isModified = -> false
      @registerCommands(editor)
      @updateGrammar(editor, word)

      projects = atom.project.getPaths()
      finished = 0
      onFinish = (code) =>
        finished++
        if finished is projects.length
          @observeNarrowInputChange(editor)
          @observeCursorPositionChange(editor)
          console.log "#{finished} finished"
        else
          console.log "#{finished} yet finished"

      for project, i in projects
        pattern = _.escapeRegExp(word)
        onData = @outputterForProject(project, editor)
        @searcher.search(pattern, {cwd: project, onData, onFinish})
