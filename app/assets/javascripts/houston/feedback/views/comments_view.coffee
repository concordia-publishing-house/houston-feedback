KEY =
  DELETE: 8
  TAB: 9
  RETURN: 13
  ESC: 27
  UP: 38
  DOWN: 40

class Houston.Feedback.CommentsView extends Backbone.View
  template: HandlebarsTemplates['houston/feedback/comments/index']
  renderComment: HandlebarsTemplates['houston/feedback/comments/show']
  renderEditComment: HandlebarsTemplates['houston/feedback/comments/edit']
  renderEditMultiple: HandlebarsTemplates['houston/feedback/comments/edit_multiple']
  renderSearchReport: HandlebarsTemplates['houston/feedback/comments/report']
  renderImportModal: HandlebarsTemplates['houston/feedback/comments/import']
  renderConfirmDeleteModal: HandlebarsTemplates['houston/feedback/comments/confirm_delete']
  renderDeleteImportedModal: HandlebarsTemplates['houston/feedback/comments/delete_imported']
  renderChangeProjectModal: HandlebarsTemplates['houston/feedback/comments/change_project']
  renderIdentifyCustomerModal: HandlebarsTemplates['houston/feedback/comments/identify_customer']
  renderNewCommentModal: HandlebarsTemplates['houston/feedback/comments/new']
  renderTagCloud: HandlebarsTemplates['houston/feedback/comments/tags']

  events:
    'submit #search_feedback': 'submitSearch'
    'change #sort_feedback': 'sort'
    'click #feedback_search_reset': 'resetSearch'
    'focus .feedback-search-result': 'resultFocused'
    'mousedown .feedback-search-result': 'resultClicked'
    'mouseup .feedback-search-result': 'resultReleased'
    'keydown': 'keydown'
    'keydown #q': 'keydownSearch'
    'click .feedback-comment-close': 'selectNone'
    'click .feedback-comment-copy-url': 'copyUrl'
    'click .feedback-remove-tag': 'removeTag'
    'keydown .feedback-new-tag': 'keydownNewTag'
    'click .btn-delete': 'deleteComments'
    'click .btn-move': 'moveComments'
    'click .btn-edit': 'editCommentText'
    'click .btn-save': 'saveCommentText'
    'keydown .feedback-text textarea': 'keydownCommentText'
    'click #toggle_extra_tags_link': 'toggleExtraTags'
    'click .feedback-tag-cloud > .feedback-tag': 'clickTag'
    'click .feedback-search-example': 'clickExample'
    'click .feedback-query': 'clickQuery'
    'click .feedback-customer-identify': 'identifyCustomer'
    'click .btn-read': 'toggleRead'
    'click .feedback-comment-copy': 'copy'
    'click .feedback-signal-strength-selector .dropdown-menu a': 'clickSignalStrength'

  initialize: ->
    @$results = @$el.find('#results')
    @sortedComments = @comments = @options.comments
    @tags = @options.tags
    @projects = @options.projects
    @customers = @options.customers
    @canCopy = ('clipboardData' in _.keys(ClipboardEvent.prototype))
    @sortOrder = 'rank'

    Mousetrap.bind "command+k command+r", (e) =>
      e.preventDefault()
      for comment in @selectedComments
        @markAsRead(comment)

    Mousetrap.bind "command+k command+u", (e) =>
      e.preventDefault()
      for comment in @selectedComments
        @markAsUnread(comment)

    Mousetrap.bind "command+k command+e", (e) =>
      e.preventDefault()
      @editCommentText()

    _.each [1..4], (i) =>
      Mousetrap.bind "command+k command+#{i}", (e) =>
        e.preventDefault()
        for comment in @selectedComments
          @setSignalStrength comment, i

    Mousetrap.bind "command+k command+0", (e) =>
      e.preventDefault()
      for comment in @selectedComments
        @setSignalStrength comment, null

    $('#import_csv_field').change (e)->
      $(e.target).closest('form').submit()

      # clear the field so that if we select the same
      # file again, we get another 'change' event.
      $(e.target).val('').attr('type', 'text').attr('type', 'file')

    $('#feedback_csv_upload_target').on 'upload:complete', (e, data)=>
      if data.ok
        @promptToImportCsv(data)
      else
        alertify.error """
        <b>There is a problem with the file "#{data.filename}"</b><br/>
        #{data.error}
        """

    $('#new_feedback_button').click =>
      @newFeedback()

    if @options.infiniteScroll
      new InfiniteScroll
        load: ($what)=>
          promise = new $.Deferred()
          @offset += 50
          promise.resolve @template
            comments: (comment.toJSON() for comment in @sortedComments.slice(@offset, @offset + 50))
          promise



  resultFocused: (e)->
    $('.feedback-search-result.anchor').removeClass('anchor')
    $result = $(e.target)
    $result.addClass('anchor')

    return if @resultIsBeingClicked

    @select e.target, 'new' unless $result.is('.selected')

  resultClicked: (e)->
    @resultIsBeingClicked = true
    @select e.target, @mode(e)

  resultReleased: (e)->
    @resultIsBeingClicked = false
    @focusEditor()

  mode: (e)->
    return 'toggle' if e.metaKey or e.ctrlKey
    return 'lasso' if e.shiftKey
    'new'

  select: (comment, mode)->
    $('.feedback-search').removeClass('feedback-search-show-instructions') if comment
    $el = @$comment(comment)

    $anchor = $('.feedback-search-result.anchor')
    mode = 'new' if mode is 'lasso' and $anchor.length is 0

    switch mode
      when 'toggle'
        $el.toggleClass('selected')
        $el.focus() if $el.hasClass('selected') and !$el.is(':focus')

      when 'lasso'
        $range = @$results.children().between($anchor, $el)
        $range.addClass('selected')

      else
        @$selection().removeClass('selected')
        $el.addClass('selected')
        $el.focus() unless $el.is(':focus')

    @selectedComments = _.compact(@comments.get(id) for id in @selectedIds())
    @$el.toggleClass 'feedback-selected', @selectedComments.length > 0
    @editSelected()

  $selection: ->
    @$el.find('.feedback-search-result.selected')

  selectedIds: ->
    $(el).attr('data-id') for el in @$selection()

  selectedId: ->
    ids = @selectedIds()
    throw "Expected only one comment to be selected, but there are #{ids.length}" unless ids.length is 1
    ids[0]

  selectPrev: (mode)->
    $prev = @$selection().first().prev('.feedback-search-result')
    if $prev and $prev.length > 0
      @select $prev, mode
    else if mode is 'new'
      @focusSearch()

  selectNext: (mode)->
    $next = @$selection().last().next('.feedback-search-result')
    if $next and $next.length > 0
      @select $next, mode

  selectNone: ->
    @select null, 'new'

  $comment: (comment)->
    return $() unless comment
    return @$comment comment[0] if _.isArray(comment)
    return @$comment comment.target if comment.target
    return $("#comment_#{comment.id}") if comment.constructor is Houston.Feedback.Comment
    $(comment).closest('.feedback-search-result')

  keydown: (e)->
    switch e.keyCode
      when KEY.UP then @selectPrev(@mode(e))
      when KEY.DOWN then @selectNext(@mode(e))
      when KEY.ESC then @focusSearch()
      when KEY.DELETE
        return unless e.metaKey
        return unless _.all @selectedComments, (comment)=> comment.get('permissions').destroy
        e.preventDefault()
        ids = (comment.id for comment in @selectedComments)
        @_deleteComments(comment_ids: ids)

  keydownSearch: (e)->
    if e.keyCode is KEY.DOWN
      e.stopImmediatePropagation()
      @selectFirstResult()

  selectFirstResult: ->
    @select @$el.find('.feedback-search-result:first'), 'new'

  submitSearch: (e)->
    @search(e)

  resetSearch: (e)->
    $('#q').val "-#no -#addressed -#invalid "
    @search(e)
    $('.feedback-search').addClass('feedback-search-show-instructions')
    $('#search_feedback').addClass('unperformed')

  search: (e)->
    return unless history.pushState

    $('#search_feedback').removeClass('unperformed')
    $('.feedback-search').removeClass('feedback-search-show-instructions')

    e.preventDefault() if e
    search = $('#search_feedback').serialize()
    url = window.location.pathname
    url = url + '?' + search unless $('#q').val() is "-#no -#addressed -#invalid "
    xlsxHref = window.location.pathname + '.xlsx?' + search
    history.pushState({}, '', url)
    $('#excel_export_button').attr('href', xlsxHref)
    start = new Date()
    $.getJSON url, (comments)=>
      @selectNone()
      @comments = new Houston.Feedback.Comments(comments, parse: true)
      @sortedComments = @applySort(@comments)
      @searchTime = (new Date() - start)
      @render()

  sort: ->
    @sortOrder = $('#sort_feedback').val()
    @sortedComments = @applySort(@comments)
    @render()

  applySort: (comments) ->
    console.log("sorting #{comments.length} comments by #{@sortOrder}")
    switch @sortOrder
      when "rank" then comments
      when "added" then comments.sortBy("createdAt").reverse()
      when "signal_strength" then comments.sortBy("averageSignalStrength").reverse()
      when "customer" then comments.sortBy (comment) -> comment.attribution().toLowerCase()
      else
        console.log("Unknown sort order: #{@sortOrder}")
        comments



  render: ->
    @offset = 0
    html = @template(comments: (comment.toJSON() for comment in @sortedComments.slice(0, 50)))
    @$results.html(html).removeClass("done")

    @$el.find('#search_report').html @renderSearchReport
      results: @comments.length
      searchTime: @searchTime

    tags = @comments.countTags()
    $('#tags_report').html @renderTagCloud
      topTags: tags.slice(0, 5)
      extraTags: tags.slice(5)

    @focusSearch()

  focusSearch: ->
    @selectNone()
    window.scrollTo(0, 0)
    $('#search_feedback input').focus().select()

  editSelected: ->
    if @selectedComments.length is 1
      @editComment @selectedComments[0]
    else if @selectedComments.length > 1
      @editMultiple @selectedComments
    else
      @editNothing()

  editComment: (comment)->
    if @timeoutId
      window.clearTimeout(@timeoutId)
      @timeoutId = null

    if comment.isUnread()
      @timeoutId = window.setTimeout =>
        @markAsRead comment, ->
          $('.feedback-comment.feedback-edit-comment .btn-read').addClass('active')
      , 1500

    context = comment.toJSON()
    context.index = $('.feedback-comment.selected').index() + 1
    context.total = @comments.length
    context.canCopy = @canCopy
    $('#feedback_edit').html @renderEditComment(context)
    $('#feedback_edit .uploader').supportImages()
    @focusEditor()

  editMultiple: (comments)->
    context =
      count: comments.length
      permissions:
        destroy: _.all comments, (comment)-> comment.get('permissions').destroy
        update: _.all comments, (comment)-> comment.get('permissions').update
      tags: []
      read: _.all comments, (comment)-> comment.get('read')

    tags = _.flatten(comment.get('tags') for comment in comments)
    for tag, array of _.groupBy(tags)
      tag.count = array.length
      percent = array.length / context.count
      percent = 0.2 if percent < 0.2
      context.tags.push
        name: tag
        percent: percent

    $('#feedback_edit').html @renderEditMultiple(context)
    @focusEditor()

  editNothing: ->
    $('#feedback_edit').html('')

  focusEditor: ->
    $('#feedback_edit').find('input').autocompleteTags(@tags).focus()

  removeTag: (e)->
    e.preventDefault()
    e.stopImmediatePropagation()
    $tag = $(e.target).closest('.feedback-tag')
    tag = $tag.text().replace(/\s/g, '')
    ids = @selectedIds()
    tags = [tag]
    $.destroy '/feedback/comments/tags', comment_ids: ids, tags: tags
      .success =>
        @comments.get(id).removeTags(tags) for id in ids
        @editSelected()
      .error ->
        console.log 'error', arguments

  keydownNewTag: (e)->
    if e.keyCode is KEY.RETURN
      e.preventDefault()
      e.stopImmediatePropagation()
      @addTag()
    if e.keyCode in [KEY.DOWN, KEY.UP]
      @addTag()

  addTag: ->
    $input = $('.feedback-new-tag')
    tags = $input.selectedTags()
    ids = @selectedIds()
    $.post '/feedback/comments/tags', comment_ids: ids, tags: tags
      .success =>
        @tags = _.uniq @tags.concat(tags)
        for id in ids
          comment = @comments.get(id)
          comment.addTags(tags)
          @redrawComment comment
        @editSelected()
      .error ->
        console.log 'error', arguments

  promptToImportCsv: (data)->
    $modal = $(@renderImportModal(data)).modal()
    $modal.on 'hidden', -> $(@).remove()

    for heading in data.headings
      if heading.text in data.customerFields
        $("#customer_field_#{heading.index}").prop "checked", true

    addTags = @activateTagControls($modal)

    $modal.find('#import_button').click =>
      addTags()

      $modal.find('button').prop('disabled', true)
      params = $modal.find('form').serializeObject()
      $.post "#{window.location.pathname}/import", params
        .success (response)=>
          $modal.modal('hide')
          alertify.success "#{response.count} comments imported"
          tags = params["tags[]"]
          if tags
            tags = [tags] unless _.isArray(tags)
            tags = _.uniq(tags)
            $("#q").val _.map(tags, (tag)-> "##{tag}").join(" ")
          @search()
        .error ->
          console.log 'error', arguments
          $modal.find('button').prop('disabled', false)



  deleteComments: (e)->
    e.preventDefault()
    ids = @selectedIds()
    imports = _.uniq(@comments.get(id).get('import') for id in ids)
    if imports.length is 1 and imports[0]
      $modal = $(@renderDeleteImportedModal()).modal()
      $modal.on 'hidden', -> $(@).remove()
      $modal.find('#delete_selected').click =>
        $modal.modal('hide')
        @_deleteComments(comment_ids: ids)
      $modal.find('#delete_imported').click =>
        $modal.modal('hide')
        @_deleteComments(import: imports[0])
    else
      $modal = $(@renderConfirmDeleteModal()).modal()
      $modal.on 'hidden', -> $(@).remove()
      $modal.find('#delete_comment_button').click =>
        $modal.modal('hide')
        @_deleteComments(comment_ids: ids)

  _deleteComments: (params)->
    $.destroy '/feedback/comments', params
      .success (response)=>
        @selectNext() or @selectPrev() or @selectNone()

        ids = response.ids
        alertify.success "#{ids.length} comments deleted"

        selectors = []
        for id in ids
          @comments.remove(id)
          selectors.push "#comment_#{id}"

        $(selectors.join(",")).remove()
      .error ->
        console.log 'error', arguments



  moveComments: (e)->
    e.preventDefault()
    ids = @selectedIds()
    html = @renderChangeProjectModal(projects: @projects)
    $modal = $(html).modal()
    $modal.on 'hidden', -> $(@).remove()
    $modal.find('#move_comments_button').click =>
      newProjectId = $modal.find('#comments_new_project').val()
      $modal.modal('hide')
      @_moveComments(comment_ids: ids, project_id: newProjectId)

  _moveComments: (params)->
    $.post '/feedback/comments/move', params
      .success (response)=>
        @selectNext() or @selectPrev() or @selectNone()

        ids = response.ids
        alertify.success "#{ids.length} comments moved"

        selectors = []
        for id in ids
          @comments.remove(id)
          selectors.push "#comment_#{id}"

        $(selectors.join(",")).remove()
      .error ->
        console.log 'error', arguments



  editCommentText: (e)->
    e.preventDefault() if e
    if @isEditingCommentText()
      @endEditCommentText()
    else
      @beginEditCommentText()

  isEditingCommentText: ->
    $('.feedback-edit-comment').hasClass('edit-text')

  beginEditCommentText: ->
    $('.feedback-edit-comment').addClass('edit-text')
    $('.btn-edit').text('Cancel')
    $('.feedback-edit-comment textarea').autosize().focus()

  endEditCommentText: ->
    $('.feedback-edit-comment').removeClass('edit-text')
    $('.btn-edit').text('Edit')
    $('.feedback-edit-comment .feedback-new-tag').focus()

  saveCommentText: (e)->
    e.preventDefault() if e

    text = $('.feedback-text.edit textarea').val()
    attributedTo = $('.feedback-customer-edit > input').val()
    comment = @comments.get @selectedId()
    comment.save(text: text, attributedTo: attributedTo)
      .success =>
        @redrawComment comment
        @editSelected()
        alertify.success "Comment updated"
        $('.feedback-edit-comment').removeClass('edit-text')
        $('.btn-edit').text('Edit')
      .error ->
        console.log 'error', arguments

  redrawComment: (comment)->
    $("#comment_#{comment.id}").html @renderComment(comment.toJSON())

  keydownCommentText: (e)->
    # Don't select another comment or jump to the search bar
    e.stopImmediatePropagation()
    switch e.keyCode
      when KEY.ESC then @endEditCommentText()
      when KEY.RETURN
        if e.metaKey or e.ctrlKey
          e.preventDefault()
          @saveCommentText()

  newFeedback: (e)->
    e.preventDefault() if e
    $modal = $(@renderNewCommentModal()).modal()
    $modal.on 'hidden', -> $(@).remove()

    $modal.find('#new_feedback_customer').focus()
    $modal.find('.uploader').supportImages()

    addTags = @activateTagControls($modal)

    submit = =>
      addTags()
      params = $modal.find('form').serialize()
      $.post window.location.pathname, params
        .success =>
          $modal.modal('hide')
          alertify.success "Comment created"
          @search()
        .error ->
          console.log 'error', arguments

    $modal.find('.feedback-new-tag').keydown (e)->
      if e.keyCode is KEY.RETURN
        if e.metaKey or e.ctrlKey
          submit()

    $modal.find('#create_button').click => submit()

  activateTagControls: ($el)->
    $el.find('#new_feedback_tags').autocompleteTags(@tags)
    $newTag = $el.find('.feedback-new-tag')

    addTags = =>
      tags = $newTag.selectedTags()
      $tags = $el.find('.feedback-tag-list')
      for tag in tags
        $tags.append """
          <span class="feedback-tag feedback-tag-new">
            #{tag}
            <input type="hidden" name="tags[]" value="#{tag}" />
            <a class="feedback-remove-tag"><i class="fa fa-close"></i></a>
          </span>
        """
      $newTag.val('')

    $newTag.keydown (e)->
      if e.keyCode is KEY.RETURN
        unless e.metaKey or e.ctrlKey
          e.preventDefault()
          addTags()

    $el.on 'click', '.feedback-remove-tag', (e)->
      $(e.target).closest('.feedback-tag-new').remove()
      $el.find('.feedback-new-tag').focus()

    addTags


  markAsRead: (comment, callback)->
    comment.markAsRead ->
      $(".feedback-search-result.feedback-comment[data-id=\"#{comment.get('id')}\"]")
        .removeClass('feedback-comment-unread')
        .addClass('feedback-comment-read')
      callback() if callback

  markAsUnread: (comment, callback)->
    comment.markAsUnread ->
      $(".feedback-search-result.feedback-comment[data-id=\"#{comment.get('id')}\"]")
        .addClass('feedback-comment-unread')
        .removeClass('feedback-comment-read')
      callback() if callback

  clickSignalStrength: (e) ->
    value = $(e.target).closest("a").data("value")
    for comment in @selectedComments
      @setSignalStrength(comment, value)

  setSignalStrength: (comment, i, callback) ->
    comment.setSignalStrength i, ->
      $("#comment_#{comment.get('id')}.feedback-search-result .feedback-comment-signal-strength")
        .html(Handlebars.helpers.signalStrengthImage(comment.get('averageSignalStrength'), {hash: {size: 16}}))
      $("#comment_#{comment.get('id')}.feedback-edit-comment .feedback-comment-signal-strength")
        .html(Handlebars.helpers.signalStrengthImage(i, {hash: {size: 20}}))
      callback() if callback



  toggleExtraTags: (e)->
    e.preventDefault() if e
    $a = $(e.target)
    $a.toggleClass('show-all-tags')
    $('#extra_tags').toggleClass 'collapsed', !$a.hasClass('show-all-tags')

  clickTag: (e)->
    e.preventDefault() if e
    $a = $(e.target).closest('a')
    tag = @getQuery $a.attr('href')
    q = $('#q').val()
    q = if q.length then "#{q} #{tag}" else tag
    $('#q').val q
    @search()

  clickExample: (e)->
    e.preventDefault() if e
    q = @getQuery $(e.target).attr('href')
    $('#q').val q
    @search()

  clickQuery: (e)->
    e.preventDefault() if e
    q = @getQuery $(e.target).attr('href')
    $('#q').val q
    @search()

  getQuery: (params)->
    @getParameterByName(params, 'q')

  # http://james.padolsey.com/javascript/bujs-1-getparameterbyname/
  getParameterByName: (params, name)->
    match = RegExp("[?&]#{name}=([^&]*)").exec(params)
    decodeURIComponent(match[1].replace(/\+/g, ' ')) if match



  toggleRead: (e)->
    if !$(e.target).hasClass('active')
      for comment in @selectedComments
        @markAsRead(comment)
    else
      for comment in @selectedComments
        @markAsUnread(comment)



  copy: (e)->
    e.preventDefault()

    # I only show the *Copy* button when there's one
    # selected comment right now, so make that assumption.
    comment = @selectedComments[0]

    $(document).one "copy", (e)=>
      e = e.originalEvent || e
      e.clipboardData.setData "text/plain", comment.text()
      e.clipboardData.setData "text/html", comment.html()
      e.preventDefault()

    document.execCommand "copy"
    alertify.success("Feedback copied!")

  copyUrl: (e)->
    e.preventDefault()

    # I only show the *Copy* button when there's one
    # selected comment right now, so make that assumption.
    comment = @selectedComments[0]
    url = App.meta("relative_url_root") + "feedback/#{comment.id}"

    $(document).one "copy", (e)=>
      e = e.originalEvent || e
      e.clipboardData.setData "text/plain", url
      e.preventDefault()

    document.execCommand "copy"
    alertify.success("Short URL copied!")



  identifyCustomer: (e)->
    e.preventDefault()

    comment = @selectedComments[0]
    attribution = comment.get('attributedTo')

    html = @renderIdentifyCustomerModal
      customers: @customers
    $modal = $(html).modal()
    $modal.on 'hidden', -> $(@).remove()
    $modal.find('#customer_name').focus()

    $modal.find('#customer_id').change ->
      $modal.find('#identify_customer_mode_existing').prop('checked', true)

    $modal.find('#customer_name').focus ->
      $modal.find('#identify_customer_mode_new').prop('checked', true)

    $modal.find('#identify_customer_button').click =>
      if $modal.find('#identify_customer_mode_existing').prop('checked')
        id = $modal.find('#customer_id').val()
        return unless id

        promise = $.post "/feedback/customers/#{id}/attribution",
          attribution: attribution
      else
        name = $modal.find('#customer_name').val()
        promise = $.post "/feedback/customers",
          attribution: attribution
          name: name

      promise.success =>
        window.location.reload()
      promise.error ->
        console.log 'error', arguments
      $modal.modal('hide')
