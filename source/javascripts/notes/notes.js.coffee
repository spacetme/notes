
join = (a, b) ->
  slash = if a.match(/\/$/) then '' else '/'
  a + slash + b

compare = (a, b) ->
  return -1 if a < b
  return 1 if b < a
  return 0

angular.module('notes', ['ngTouch', 'notesDropbox'])

.config ($provide) ->

  # http://stackoverflow.com/questions/18611214/turn-off-url-manipulation-in-angularjs
 
  $provide.decorator '$browser', ($delegate) ->
    $delegate.onUrlChange = ->
    $delegate.url = -> ""
    $delegate

.constant 'DROPBOX_APP_KEY', 'qrsu984sawpgqxm'

.directive 'notesCodemirror', ->
  scope:
    text: '=notesCodemirror'
  link: (scope, element, attrs) ->
    editor = CodeMirror(element[0],
      mode: 'gfm',
      lineNumbers: true,
      theme: 'spacetme',
      lineWrapping: true)
    scope.$watch 'text', (text) ->
      if editor.getDoc().getValue() != text
        editor.getDoc().setValue(text)
    timeout = null
    editor.on 'change', ->
      clearTimeout(timeout) if timeout?
      timeout = setTimeout (->
        scope.$apply -> scope.text = editor.getDoc().getValue()), 100

.service 'stLocation', ($rootScope) ->
  
  loc = { }

  loc.path = '/'

  HASHBANG = /^#?!\//

  getFromHash = ->
    hash = location.hash
    if hash.match(HASHBANG)
      loc.path = '/' + hash.replace(HASHBANG, '')
    else
      loc.path = '/'

  getFromHash()

  window.addEventListener 'hashchange', ->
    $rootScope.$apply -> getFromHash()

  loc.go = (path) ->
    if path.match(/^\//)
      location.hash = '#!' + path
      loc.path = path
    else
      loc.path = '/'
      if history.pushState
        history.pushState {}, "", location.pathname + location.search
      else
        location.hash = '#'

  return loc


.controller 'MainController', ($scope, dropbox, FileEditor, stLocation) ->

  $scope.host = location.host

  $scope.dropbox = dropbox
  $scope.appLoaded = true

  $scope.state =
    name: 'folder-listing'

  $scope.$watch (-> stLocation.path), (path) ->
    if path == '/' || path.match(/\/$/)
      $scope.state.name = 'folder-listing'
    else
      $scope.state.name = 'file-view'
      $scope.state.files = [
        FileEditor(path)
      ]

  $scope.openFile = (path) ->
    stLocation.go(path)

  $scope.closeFile = () ->
    stLocation.go('')

  $scope.discardFile = (file) ->
    if confirm('Are you sure? All your changes will be lost then!')
      delete localStorage['file:' + file.path]
      $scope.closeFile()

.factory 'Operations', ($q) ->

  () ->
    
    operations = { }
    operations.items = [ ]

    operations.run = (callback) ->

      defer = $q.defer()

      task =
        name: 'Unnamed Task'
        action: -> throw new Error("No action given!")

      callback(task)

      item =
        task: task
        retry: ->
        status: 'pending'

      run = ->
        item.status = 'running'
        task.action().then(done, fail)

      done = (result) ->
        item.status = 'succeeded'
        defer.resolve(result)
        remove()

      fail = (reason) ->
        item.status = 'failed'
        item.reason = reason.toString()
      
      remove = ->
        for c, i in operations.items
          if c == item
            operations.items.splice(i, 1)
            return

      item.retry = ->
        if item.status == 'failed'
          run()

      item.letItGo = ->
        if item.status == 'failed'
          remove()


      operations.items.push(item)
      run()

      defer.promise

    return operations

.directive 'spOperationsList', ->

  templateUrl: 'templates/operations/list.html'

  scope:
    operations: '=spOperationsList'


.factory 'files', (dropbox, $rootScope, $q, Operations) ->

  files = { }

  localItems = (path) ->

    path += '/' unless path.match(/\/$/)

    hash = { }
    do ->
      for i in [0...localStorage.length]
        key = localStorage.key(i)
        if key.substr(0, 5) == 'file:'
          key = key.substr(5)
          full = key
          if key.substr(0, path.length) == path
            key = key.substr(path.length)
            key = key.replace(/\/[\s\S]+$/, '/')
            hash[key] = full

    do ->
      modified = (fullPath) ->
        try
          data = JSON.parse(localStorage['file:' + fullPath])
          !!data.changed
        catch
          false
      for own name, full of hash
        norm = name.replace(/\/$/, '')
        type = if name.match(/\/$/) then 'folder' else 'file'
        changed = type == 'file' && modified(full)
        {
          localKey: name
          storageKey: 'file:' + full
          type: type
          name: norm
          path: join(path, norm)
          local: true
          changed: changed
        }

  files.at = (path) ->

    folder = { path: path }

    folder.operations = Operations()
    folder.items = locals = localItems(path)

    folder.newFolder = (name) ->
      folder.operations.run((task) ->
        task.name = 'Creating new folder...'
        task.action = -> dropbox.mkdir(join(path, name))
      )
      .then((stat) -> load('Refreshing folder contents...').then(-> stat))

    attachLocals = (result) ->
      hash = { }
      result.forEach (item) ->
        slash = if item.type == 'folder' then '/' else ''
        hash[item.name + slash] = item
      locals.forEach (item) ->
        if (remote = hash[item.localKey])
          remote.changed = item.changed
        else if item.type == 'file' && !item.changed
          delete localStorage[item.storageKey]
        else
          result.push(item)

    load = (text) ->
      folder.operations.run((task) ->
        task.name = text
        task.action = -> dropbox.readdir(path, { })
      )
      .then ({ files }) ->
        rank = { folder: 1, file: 2 }
        result = files.map((stat) ->
          type: if stat.isFolder then 'folder' else 'file'
          name: stat.name
          path: stat.path)
        attachLocals(result)
        result.sort (a, b) ->
          diff = rank[a.type] - rank[b.type]
          return diff if diff != 0
          return compare(a.name, b.name)
        folder.items = result

    load 'Loading folder contents...'

    return folder

  return files


.controller 'FolderListingController', ($scope, dropbox, files) ->

  $scope.columns = [files.at('/')]

  spawnColumn = (column, path) ->
    index = $scope.columns.indexOf(column)
    if index > -1
      $scope.columns.splice(index + 1)
    $scope.columns.push(files.at(path))

  $scope.click = (item, column) ->
    if item.type == 'folder'
      column.selectedItem = item
      spawnColumn(column, item.path)
    else
      $scope.openFile(item.path)

  $scope.newFile = (name, column) ->
    name += '.md' if !name.match(/\.\w+$/)
    $scope.openFile(join(column.path, name))

  $scope.newFolder = (name, column) ->
    column.newFolder(name).then (stat) ->
      console.log(column.items, name)
      for item in column.items
        if item.name == name
          column.selectedItem = item
          break
      spawnColumn(column, stat.path)

.directive 'notesLinkForm', ->
  link: (scope, element, attrs) ->
    element.find('form').css('display', 'none')
    element.find('a').on 'click', ->
      element.find('a').css('display', 'none')
      element.find('form').css('display', '')
      element.find('input')[0].focus()
    element.find('input').on 'blur', ->
      if this.value == ''
        element.find('form').css('display', 'none')
        element.find('a').css('display', '')


.factory 'FileEditor', (dropbox, Operations, $q, $rootScope, $timeout) ->

  (path) ->

    newFile = false
    editor = { }

    editor.operations = new Operations()
    editor.path = path

    editor.tag = ->
      editor.versionTag || (if newFile then '<new file>' else '-')

    editor.contents = ""
    editor.versionTag = null
    editor.changed = false

    editor.save = ->
      editor.operations.run (task) ->
        task.name = 'Saving file...'
        task.action = ->
          dropbox.writeFile(path, editor.contents, editor.versionTag)
            .then ({ versionTag }) ->
              editor.versionTag = versionTag
              editor.changed = false

    do ->
      info = localStorage['file:' + path]
      unless info?
        console.log "#{path} not in cache..."
        return
      try
        info = JSON.parse(info)
        throw "No contents" unless typeof info.contents == 'string'
        throw "Invalid version tag" unless info.versionTag == null || typeof info.versionTag == 'string'
        editor.contents = info.contents
        editor.versionTag = info.versionTag
        if typeof info.changed == 'boolean'
          editor.changed = info.changed
      catch
        console.log "Unable to parse info for #{path}: #{info}"

    newestPromise = editor.operations.run (task) ->
      task.name = 'Loading newest file contents...'
      task.action = ->
        dropbox.readFile(path)
          .catch (error) ->
            if error.status == 404
              newFile = true
              { contents: "", versionTag: null }
            else
              $q.reject(error)

    basePromise = editor.operations.run (task) ->
      task.name = 'Loading base file contents...'
      task.action = ->
        return $q.when(null) if editor.versionTag == null
        dropbox.readFile(path, editor.versionTag)
          .catch (error) ->
            console.error("Error loading base contents", error)
            null

    changed = ->
      localStorage['file:' + path] = JSON.stringify(
        contents: editor.contents
        versionTag: editor.versionTag
        changed: editor.changed)

    $rootScope.$watch (-> editor.contents), (-> editor.changed = true), true
    $rootScope.$watch (-> [editor.contents, editor.changed, editor.versionTag]), changed, true

    $q.all({ newest: newestPromise, base: basePromise }).then ({ newest, base }) ->
      if base == null # then replace everything!
        if not newFile
          editor.contents = newest.contents
          editor.versionTag = newest.versionTag
      else if base.versionTag == newest.versionTag
        # then do nothing
      else if not newFile
        dmp = new diff_match_patch()
        text1 = base.contents
        text2 = editor.contents
        patch = dmp.patch_make(text1, text2)
        results = dmp.patch_apply(patch, newest.contents)
        editor.contents = results[0]
        editor.versionTag = newest.versionTag
        console.log(results[1])

      $timeout (->
        if editor.contents == newest.contents
          editor.changed = false
        else
          editor.changed = true), 0

      changed()

    return editor










