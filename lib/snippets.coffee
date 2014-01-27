path = require 'path'

async = require 'async'
CSON = require 'season'
fs = require 'fs-plus'

Snippet = require './snippet'
SnippetExpansion = require './snippet-expansion'

module.exports =
  loaded: false

  activate: ->
    @loadAll()
    atom.workspaceView.eachEditorView (editorView) =>
      @enableSnippetsInEditor(editorView) if editorView.attached

  loadAll: ->
    userSnippetsPath = CSON.resolve(path.join(atom.getConfigDirPath(), 'snippets'))
    if userSnippetsPath
      @loadSnippetsFile userSnippetsPath, => @loadPackageSnippets()
    else
      @loadPackageSnippets()

  loadPackageSnippets: ->
    packages = atom.packages.getLoadedPackages()
    snippetsDirPaths = []
    snippetsDirPaths.push(path.join(pack.path, 'snippets')) for pack in packages
    async.eachSeries snippetsDirPaths, @loadSnippetsDirectory.bind(this), @doneLoading.bind(this)

  doneLoading: ->
    @loaded = true

  loadSnippetsDirectory: (snippetsDirPath, callback) ->
    return callback() unless fs.isDirectorySync(snippetsDirPath)

    fs.readdir snippetsDirPath, (error, entries) =>
      if error?
        console.warn(error)
        callback()
      else
        paths = entries.map (file) -> path.join(snippetsDirPath, file)
        async.eachSeries(paths, @loadSnippetsFile.bind(this), callback)

  loadSnippetsFile: (filePath, callback) ->
    return callback() unless CSON.isObjectPath(filePath)

    CSON.readFile filePath, (error, object) =>
      if error?
        console.warn "Error reading snippets file '#{filePath}': #{error.stack ? error}"
      else
        @add(@translateTextmateSnippet(object))
      callback()

  translateTextmateSnippet: (snippet) ->
    {scope, name, content, tabTrigger} = snippet

    # Treat it as an Atom snippet if none of the TextMate snippet fields
    # are present
    return snippet unless scope or name or content or tabTrigger

    scope = atom.syntax.cssSelectorFromScopeSelector(scope) if scope
    scope ?= '*'
    snippetsByScope = {}
    snippetsByName = {}
    snippetsByScope[scope] = snippetsByName
    snippetsByName[name] = { prefix: tabTrigger, body: content }
    snippetsByScope

  add: (snippetsBySelector) ->
    for selector, snippetsByName of snippetsBySelector
      snippetsByPrefix = {}
      for name, attributes of snippetsByName
        { prefix, body, bodyTree } = attributes
        # if `add` isn't called by the loader task (in specs for example), we need to parse the body
        bodyTree ?= @getBodyParser().parse(body)
        snippet = new Snippet({name, prefix, bodyTree})
        snippetsByPrefix[snippet.prefix] = snippet
      atom.syntax.addProperties(selector, snippets: snippetsByPrefix)

  getBodyParser: ->
    @bodyParser ?= require './snippet-body-parser'

  enableSnippetsInEditor: (editorView) ->
    editor = editorView.getEditor()
    editorView.command 'snippets:expand', (e) =>
      unless editor.getSelection().isEmpty()
        e.abortKeyBinding()
        return

      prefix = editor.getCursor().getCurrentWordPrefix()
      if snippet = atom.syntax.getProperty(editor.getCursorScopes(), "snippets.#{prefix}")
        editor.transact ->
          new SnippetExpansion(snippet, editor)
      else
        e.abortKeyBinding()

    editorView.command 'snippets:next-tab-stop', (e) ->
      unless editor.snippetExpansion?.goToNextTabStop()
        e.abortKeyBinding()

    editorView.command 'snippets:previous-tab-stop', (e) ->
      unless editor.snippetExpansion?.goToPreviousTabStop()
        e.abortKeyBinding()
