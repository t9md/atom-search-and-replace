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
    @locked = true
    range = editor.setTextInBufferRange(range, text)
    @locked = false
    range

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

  locked: null
  isLocked: -> @locked

  observeCursorPositionChange: (editor) ->
    editor.onDidChangeCursorPosition ({oldBufferPosition, newBufferPosition}) =>
      return if @isLocked()
      return unless @isAutoReveal()
      @jump(editor, reveal: true) if (oldBufferPosition.row isnt newBufferPosition.row)

  registerCommands: (editor) ->
    editorElement = atom.views.getView(editor)
    editorElement.classList.add('search-and-replace')
    atom.commands.add editorElement,
      'search-and-replace:jump': => @jump(editor)
      'search-and-replace:reveal': => @jump(editor, reveal: true)
      'search-and-replace:toggle-auto-reveal': => @autoReveal = not @autoReveal

  jump: (editor, options={reveal: false}) ->
    {row} = editor.getCursorBufferPosition()

    unless entry = _.detect(@candidates, (entry) -> entry.row is row)
      return

    {fullPath, point} = entry
    point = new Point(parseInt(point[0]) - 1, parseInt(point[1]))

    highlightRow = (editor, row) ->
      range = editor.bufferRangeForBufferRow(point.row)
      decorateRange editor, range,
        class: 'search-and-replace-flash'
        timeout: 300

    originalPane = atom.workspace.getActivePane()
    openInAdjacentPane(fullPath, {pending: true}).then (_editor) ->
      smartScrollToBufferPosition(_editor, point)
      highlightRow(_editor, point.row)

      if options.reveal
        originalPane.activate()
      else
        _editor.setCursorBufferPosition(point)

  observeNarrowInputChange: (editor) ->
    buffer = editor.getBuffer()
    currentSearch = buffer.lineForRow(0)
    buffer.onDidChange ({newRange}) =>
      return unless (newRange.start.row is 0)
      @refresh(editor, buffer.lineForRow(0))

    # buffer.onDidStopChanging =>
    #   if currentSearch isnt buffer.lineForRow(0)
    #     currentSearch = buffer.lineForRow(0)
    #     @refresh(editor, currentSearch)

  parseLine: (line) ->
    m = line.match(/^(.*?):(\d+):(\d+):(.*)$/)
    if m?
      {
        filePath: m[1]
        point: [m[2], m[3]]
        lineText: m[4]
      }
    else
      console.log 'nmatch!', line
      {}

  formatLine: (lineParsed) ->
    {filePath, point, lineText} = lineParsed
    "#{point[0]}:#{point[1]}:#{lineText}"

  outputterForProject: (project, editor) ->
    initialData = true
    (event) =>
      {data} = event
      if initialData
        projectHeader = "# #{path.basename(project)}\n"
        @insertAtLastRow(editor, projectHeader)
        initialData = false

      currentFile = null
      for line in data.split("\n") when line.length
        entry = @parseLine(line)
        if entry.filePath isnt currentFile
          currentFile = entry.filePath
          @insertAtLastRow(editor, "## #{currentFile}\n")
        range = @insertAtLastRow(editor, @formatLine(entry) + "\n")
        entry.fullPath = path.join(project, entry.filePath)
        entry.row = range.start.row
        @saveCandidate(entry)

  saveCandidate: (entry) ->
    @candidates ?= []
    @candidates.push(entry)

  # findCandidate: (fn) -> _.detect @candidates, (entry) -> fn(entry)

  renderCandidate: (editor, candidates) ->
    render = (text) ->
      rangeToRefresh = [[1, 0], editor.getEofBufferPosition()]
      editor.setTextInBufferRange(rangeToRefresh, text)

    render(
      candidates.map (entry, i) =>
        entry.row = i+1
        console.log entry.row
        @formatLine(entry)
      .join("\n")
    )

  refresh: (editor, words) ->
    words = _.compact(words.split(/\s+/))
    candidates = @candidates

    for word in words
      pattern = ///#{_.escapeRegExp(word)}///
      candidates = _.filter(candidates, ({lineText}) -> lineText.match(pattern))
      console.log word, candidates
    @renderCandidate(editor, candidates)

  searchersRunning: []
  search: (word) ->
    @candidates = null
    openInAdjacentPane(null).then (editor) =>
      editor.insertText("\n")
      editor.setCursorBufferPosition([0, 0])
      editor.isModified = -> false
      @registerCommands(editor)
      @updateGrammar(editor, word)
      @observeNarrowInputChange(editor)
      @observeCursorPositionChange(editor)

      projects = atom.project.getPaths()
      finished = 0
      onFinish = (code) ->
        finished++
        if finished is projects.length
          console.log "#{finished} finished"
        else
          console.log "#{finished} yet finished"

      for project, i in projects
        pattern = _.escapeRegExp(word)
        onData = @outputterForProject(project, editor)
        @searchersRunning.push(@searcher.search(pattern, {cwd: project, onData, onFinish}))
