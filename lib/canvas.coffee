class GridView

  constructor: (@tw, @th, @w, @h) ->
    @el = document.createElement 'canvas'
    @ctx = @el.getContext '2d'


