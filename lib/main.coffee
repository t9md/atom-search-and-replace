{CompositeDisposable, Emitter, Point} = require 'atom'
path = require 'path'
_ = require 'underscore-plus'
Searcher = require './searcher'
Grammar = require atom.config.resourcePath + "/node_modules/first-mate/lib/grammar.js"
CSON = null
grammarPath = path.join(__dirname, 'grammar', 'search-and-replace.cson')
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
    atom.commands.add 'atom-text-editor',
      'search-and-replace:search-in-file': =>
        @searchInFile()

  deactivate: ->
    @subscriptions.dispose()
    {@subscriptions, @emitter} = {}

  subscribe: (args...) ->
    @subscriptions.add args...

  provideSearchAndReplace: ->
    search: @search.bind(this)
    searchInFile: @searchInFile.bind(this)

  updateGrammar: (editor, narrowWords=null) ->
    grammarPath = path.join(__dirname, 'grammar', 'search-and-replace.cson')
    unless @keywordGrammarObject?
      CSON ?= require 'season'
      @keywordGrammarObject = CSON.readFileSync(grammarPath)

    atom.grammars.removeGrammarForScopeName('source.search-and-replace')
    if @searchWord?
      @keywordGrammarObject.patterns[0].match = "(?i:#{_.escapeRegExp(@searchWord)})"
    @keywordGrammarObject.patterns[1].match = narrowWords ? '$a'
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
      'search-and-replace:jump': => @jump(editor, {close: true})
      'search-and-replace:jump-with-keep-result': => @jump(editor)
      'search-and-replace:reveal': => @jump(editor, reveal: true)
      'search-and-replace:toggle-auto-reveal': => @autoReveal = not @autoReveal

  jump: (editor, options={}) ->
    {reveal, close} = options
    {row} = editor.getCursorBufferPosition()

    unless entry = @rowToEntry[row]
      return

    {project, fullPath, filePath, point} = entry
    fullPath ?= path.join(project, filePath)
    point = new Point(parseInt(point[0]) - 1, parseInt(point[1]))

    highlightRow = (editor, row) ->
      range = editor.bufferRangeForBufferRow(point.row)
      decorateRange editor, range,
        class: 'search-and-replace-flash'
        timeout: 300

    originalPane = atom.workspace.getActivePane()
    resultEditor = atom.workspace.getActiveTextEditor()
    openInAdjacentPane(fullPath, {pending: true}).then (_editor) ->
      smartScrollToBufferPosition(_editor, point)
      highlightRow(_editor, point.row)

      if options.reveal
        originalPane.activate()
      else
        _editor.setCursorBufferPosition(point)
        resultEditor.destroy() if close

  observeNarrowInputChange: (editor) ->
    buffer = editor.getBuffer()
    currentSearch = buffer.lineForRow(0)
    buffer.onDidChange ({newRange}) =>
      return unless (newRange.start.row is 0)
      @refresh(editor, buffer.lineForRow(0))

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
    ({data}) =>
      lines = data.split("\n")
      for line in lines when line.length
        entry = @parseLine(line)
        entry.project = project
        (@candidates ?= []).push(entry)
      @renderCandidate(editor, @candidates)

  renderCandidate: (editor, candidates, {replace, header}={}) ->
    @locked = true
    try
      replace ?= false
      if replace
        @rowToEntry = {}
      else
        @rowToEntry ?= {}

      lines = []
      currentProject = null
      currentFile = null
      initialRow = if replace then 1 else editor.getLastBufferRow()
      for entry in candidates
        if @showHeader
          if entry.project isnt currentProject
            currentProject = entry.project
            lines.push("# #{path.basename(currentProject)}")

          if entry.filePath isnt currentFile
            currentFile = entry.filePath
            lines.push("## #{currentFile}")
          lines.push(" " + @formatLine(entry))
        else
          lines.push(@formatLine(entry))
        @rowToEntry[initialRow + (lines.length - 1)] = entry

      range = [[initialRow, 0], editor.getEofBufferPosition()]
      editor.setTextInBufferRange(range, lines.join("\n") + "\n")
    finally
      @locked = false

  refresh: (editor, words) ->
    words = _.compact(words.split(/\s+/))
    candidates = @candidates

    for word in words
      pattern = ///#{_.escapeRegExp(word)}///i
      candidates = _.filter(candidates, ({lineText}) -> lineText.match(pattern))
    @renderCandidate(editor, candidates, {replace: true})
    if words.length
      @updateGrammar(editor, "(?i:#{words.map(_.escapeRegExp).join('|')})")
    else
      @updateGrammar(editor)

  searchInFile: (@searchWord=null) ->
    @candidates = null
    @showHeader = false

    # [FIXME] refresh result when editor is modified. e.g observe onDidStopChanging

    editor = atom.workspace.getActiveTextEditor()
    filePath = editor.getPath()
    for line, i in editor.getBuffer().getLines()
      entry =
        fullPath: filePath
        point: [i+1, 0]
        lineText: line
      (@candidates ?= []).push(entry)

    openInAdjacentPane(null).then (editor) =>
      editor.insertText("\n")
      editor.setCursorBufferPosition([0, 0])
      editor.isModified = -> false
      @registerCommands(editor)
      @updateGrammar(editor)
      @observeNarrowInputChange(editor)
      @observeCursorPositionChange(editor)
      @renderCandidate(editor, @candidates)
      editor

  searchersRunning: []
  search: (@searchWord) ->
    @candidates = null
    @showHeader = true
    openInAdjacentPane(null).then (editor) =>
      editor.insertText("\n")
      # editor.getTitle -> 's&r:project'
      editor.setCursorBufferPosition([0, 0])
      editor.isModified = -> false
      @registerCommands(editor)
      @updateGrammar(editor)
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
        pattern = _.escapeRegExp(@searchWord)
        onData = @outputterForProject(project, editor)
        @searchersRunning.push(@searcher.search(pattern, {cwd: project, onData, onFinish}))

      editor
    # editorElement = atom.views.getView(editor)
    # atom.commands.dispatch(editorElement, 'vim-mode-plus:activate-insert-mode')
