
angular.module('notesDropbox', [])

.factory 'dropboxClient', (DROPBOX_APP_KEY) ->

  if Dropbox?
    new Dropbox.Client(key: DROPBOX_APP_KEY)
  else
    console.log "Dropbox not found... Probably offline!"
    offline = -> new Error("Dropbox is offline!")
    authenticate: ->
    isAuthenticated: -> true
    readdir: (path, options, callback) -> callback(offline())
    mkdir: (path, callback) -> callback(offline())
    readFile: (path, options, callback) -> callback(offline())
    writeFile: (path, contents, options, callback) -> callback(offline())

.factory 'dropbox', (dropboxClient, $q) ->

  dropbox = { }

  dropboxClient.authenticate { interactive: false }, (error) ->
    if error
      alert "Authentication error! #{error}"

  dropbox.authenticated = dropboxClient.isAuthenticated()

  dropbox.authenticate = ->
    dropboxClient.authenticate()

  callbackify = (defer, transform) ->
    (err, args...) ->
      if err
        defer.reject(err)
      else
        defer.resolve(transform(args...))

  promisify = (callback) ->
    defer = $q.defer()
    callback(defer)
    defer.promise

  dropbox.readdir = (path, options) ->
    promisify (defer) ->
      transform = (filenames, folder, files) -> { folder, files }
      dropboxClient.readdir(path, options, callbackify(defer, transform))

  dropbox.mkdir = (path) ->
    promisify (defer) ->
      transform = (stat) -> stat
      dropboxClient.mkdir(path, callbackify(defer, transform))

  dropbox.readFile = (path, versionTag=null) ->
    promisify (defer) ->
      options = { }
      options.versionTag = versionTag if versionTag?
      transform = (contents, { versionTag }) -> { contents, versionTag }
      dropboxClient.readFile(path, options, callbackify(defer, transform))

  dropbox.writeFile = (path, contents, versionTag=null) ->
    promisify (defer) ->
      options = { }
      options.lastVersionTag = versionTag if versionTag?
      transform = (stat) -> stat
      dropboxClient.writeFile(path, contents, options, callbackify(defer, transform))


  return dropbox


  



  

