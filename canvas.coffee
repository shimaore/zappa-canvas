#!/usr/bin/env coffee

require('zappa') ->
  @enable 'default layout', 'serve jquery',
    'serve sammy' # , 'minify'

  @get '/': ->
    @render 'index'

  # TODO Load from storage at startup
  history = [{do:'wipe'}]
  redo = []

  # Canvas server
  @on connection: ->
    # Update the newly-connected client with history
    console.log "Client #{@id} connected"
    @emit 'run commands': {commands:history}

  @on disconnect: ->
    console.log "Client #{@id} disconnected"
    @broadcast log: {text:"#{@client.nickname} disconnected."}
    delete @client.nickname

  @on 'canvas clear': ->
    history = [{do:'wipe'}]
    @broadcast 'run commands': {commands:history}
    @emit      'run commands': {commands:history}
    @broadcast log: {text:"Cleared by #{@client.nickname}!"}
    @emit      log: {text:"Cleared by #{@client.nickname}!"}

  @on 'canvas line': ->
    command = do:'line',from:@data.from,to:@data.to,author:@client.nickname
    history.push command
    @broadcast 'run commands': {commands:[command]}

  @on 'canvas undo': ->
    if history.length <= 1
      @emit log: {text: "Nothing to undo"}
      return
    redo.push history.pop()
    @broadcast 'run commands': {commands:history}
    @emit      'run commands': {commands:history}

  @on 'canvas redo': ->
    if redo.length < 1
      @emit log: {text: "Nothing to redo"}
      return
    command = redo.pop()
    history.push command
    @broadcast 'run commands': {commands:[command]}
    @emit      'run commands': {commands:[command]}

  # Chat Server (based on zappa's chat example)
  @on 'set nickname': ->
    @client.nickname = @data.nickname
    console.log "#{@client.nickname} connected"
    @broadcast log: {text: "#{@client.nickname} connected"}
    @emit      log: {text: "#{@client.nickname} connected"}

  @on said: ->
    @broadcast said: {nickname: @client.nickname, text: @data.text}
    @emit      said: {nickname: @client.nickname, text: @data.text}

  @shared '/shared.js': ->

  @client '/index.js': ->

    # See http://www.williammalone.com/articles/create-html5-canvas-javascript-drawing-app/
    $.fn.draw = (cb) ->
      precision = 2
      paint = false
      last_point = null
      @mousedown (e) ->
        point =
          x: e.pageX - @offsetLeft
          y: e.pageY - @offsetTop

        paint = true
        cb point, point
        last_point = point

      @mousemove (e) ->
        if paint
          point =
            x: e.pageX - @offsetLeft
            y: e.pageY - @offsetTop
          dx = point.x - last_point.x
          dy = point.y - last_point.y
          if -precision <= dx <= precision or -precision <= dy <= precision
            return
          cb last_point, point
          last_point = point

      @mouseup (e) ->
        paint = false

      @mouseleave (e) ->
        paint = false

    canvas_ctx = null
    canvas_width = null
    canvas_height = null

    render_command = (command) ->

      if not canvas_ctx
        log "Canvas not ready yet"
        return

      switch command.do
        when 'wipe'
          # Remove any text div
          # Wipe canvas
          canvas_ctx.clearRect(0,0,canvas_width,canvas_height)

        when 'line'
          canvas_ctx.strokeStyle = '#df4b26'
          canvas_ctx.lineJoin = 'round'
          canvas_ctx.lineWidth = 5

          canvas_ctx.beginPath()
          canvas_ctx.moveTo command.from.x, command.from.y
          canvas_ctx.lineTo command.to.x,   command.to.y
          canvas_ctx.stroke()
          
    log = (text) ->
      console.log text
      $('#log').prepend "<p>#{text}</p>"

    @on connection: ->
      log "Connected as #{@id}"

    @on disconnect: ->
      log "Disconnected"

    @on log: ->
      log @data.text

    @on said: ->
      log """
        <span class="author">#{@data.nickname}</span>
        said:
        <span class="message">#{@data.text}</span>
      """

    @get '#/': =>

      # Whiteboard
      $('#canvas').each ->
        if @getContext
          canvas_ctx = @getContext '2d'
          if canvas_ctx
            log 'Canvas is ready'
          canvas_width = @width
          canvas_height = @height
        else
          log 'Canvas is not supported'

      $('#canvas').draw (from,to) =>
        @emit 'canvas line': {from:from,to:to}
        render_command do:'line',from:from,to:to

      $('#undo').click =>
        @emit 'canvas undo': {}
        return false

      $('#redo').click =>
        @emit 'canvas redo': {}
        return false

      # Chat
      @emit 'set nickname': {nickname: prompt 'Pick a nickname!'}

      $('#box').focus()

      $('button').click (e) =>
        @emit said: {text: $('#box').val()}
        $('#box').val('').focus()
        e.preventDefault()

    @get '#/clear': =>
      @emit 'canvas clear': {}

    @get '#/draw': ->
      # Select drawing tool

    @get '#/text': ->
      # Create new text box


    @on 'run commands': ->
      render_command command for command in @data.commands

    # Connect to socket.io 
    @connect()

  @css '/index.css': '''
    canvas { border: 1px solid black; }
    a, span#undo, span#redo { margin: 2px; }
    .author { font-style: italic; }
    .message { font-weight: bold; }
  '''

  @view index: ->
    @title = 'Whiteboard!'
    @scripts = ['/socket.io/socket.io', '/zappa/jquery',
      '/zappa/sammy', '/zappa/zappa', '/shared', '/index']
    @stylesheets = ['/index']

    h1 @title
    div class:'board', ->
      canvas width:1000, height:300, id:'canvas'

    a href:'#/clear', 'Clear'
    span id:'undo', 'Undo'
    span id:'redo', 'Redo'
    a href:'#/draw', 'Draw'
    a href:'#/text', 'Text'

    form ->
      input id: 'box'
      button 'Send'
    div id:'log'
