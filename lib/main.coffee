{CompositeDisposable, Emitter} = require 'atom'

module.exports =
  activate: ->
    @subscriptions = new CompositeDisposable
    @subscribe atom.commands.add 'atom-text-editor',
      'search-and-replace:start': =>
        @searchAndReplace()

  deactivate: ->
    @subscriptions.dispose()
    {@subscriptions, @emitter} = {}

  subscribe: (args...) ->
    @subscriptions.add args...

  searchAndReplace: ->
    console.log 'search-and-replace!'
