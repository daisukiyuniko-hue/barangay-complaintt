# ============================================================================
#  Controllers/ComplaintController.ps1
#  Create / Read / Update / Delete for the core entity: Complaints
# ============================================================================

function Get-VisibleComplaints {
    <#
        Residents only ever see their own reports. Administrators see all of them.
    #>
    param($Ctx)

    $user = $Ctx.Auth.User
    $all  = @(Get-AllComplaints)

    if (Test-IsAdmin $user) { return $all }
    return @($all | Where-Object { [string]$_.reporterId -eq [string]$user.id })
}

# ------------------------------------------------------------------- READ ---
function Invoke-ComplaintList {
    param($Ctx)

    $user      = $Ctx.Auth.User
    $csrf      = Get-CsrfToken -Ctx $Ctx
    $isAdmin   = Test-IsAdmin $user
    $pageSize  = [int]$global:Config.PageSize

    $search   = Get-QueryValue -Request $Ctx.Request -Name 'q'
    $status   = Get-QueryValue -Request $Ctx.Request -Name 'status'
    $category = Get-QueryValue -Request $Ctx.Request -Name 'category'
    $priority = Get-QueryValue -Request $Ctx.Request -Name 'priority'
    $page     = 1
    $pageRaw  = Get-QueryValue -Request $Ctx.Request -Name 'page' -Default '1'
    if ([int]::TryParse($pageRaw, [ref]$page) -eq $false -or $page -lt 1) { $page = 1 }

    # Unknown filter values would silently hide everything, so reset them.
    if ($status   -and ($global:Statuses.Value   -notcontains $status))   { $status = '' }
    if ($category -and ($global:Categories.Value -notcontains $category)) { $category = '' }
    if ($priority -and ($global:Priorities.Value -notcontains $priority)) { $priority = '' }

    $items = @(Get-VisibleComplaints -Ctx $Ctx)

    if ($search) {
        $needle = $search.ToLowerInvariant()
        $items = @($items | Where-Object {
            ([string]$_.title).ToLowerInvariant().Contains($needle) -or
            ([string]$_.description).ToLowerInvariant().Contains($needle) -or
            ([string]$_.referenceNo).ToLowerInvariant().Contains($needle) -or
            ([string]$_.location).ToLowerInvariant().Contains($needle) -or
            ([string]$_.reporterName).ToLowerInvariant().Contains($needle)
        })
    }
    if ($status)   { $items = @($items | Where-Object { $_.status   -eq $status }) }
    if ($category) { $items = @($items | Where-Object { $_.category -eq $category }) }
    if ($priority) { $items = @($items | Where-Object { $_.priority -eq $priority }) }

    # Newest first
    $items = @($items | Sort-Object -Property createdAt -Descending)

    $total      = $items.Count
    $totalPages = [Math]::Max(1, [Math]::Ceiling($total / $pageSize))
    if ($page -gt $totalPages) { $page = $totalPages }
    $offset  = ($page - 1) * $pageSize
    $visible = @($items | Select-Object -Skip $offset -First $pageSize)

    # Build the query string again for pagination + sort links
    $qsParts = @('q='   + [System.Net.WebUtility]::UrlEncode($search),
                 'status='   + [System.Net.WebUtility]::UrlEncode($status),
                 'category=' + [System.Net.WebUtility]::UrlEncode($category),
                 'priority=' + [System.Net.WebUtility]::UrlEncode($priority))
    $baseUrl = '/complaints?' + ($qsParts -join '&')

    $anyFilter = (-not [string]::IsNullOrWhiteSpace($search) -or $status -or $category -or $priority)

    # ---- filter panel -----------------------------------------------------
    $statusOptions   = '<option value="">All statuses</option>'   + (New-SelectOptions -Items $global:Statuses   -Selected $status)
    $categoryOptions = '<option value="">All categories</option>' + (New-SelectOptions -Items $global:Categories -Selected $category)
    $priorityOptions = '<option value="">All priorities</option>' + (New-SelectOptions -Items $global:Priorities -Selected $priority)

    $rowsHtml = ''
    foreach ($c in $visible) {
        $rowsHtml += New-ComplaintRow -Complaint $c -Viewer $user
    }
    if ($visible.Count -eq 0) {
        if ($anyFilter) {
            $rowsHtml = New-EmptyState -Icon '&#128269;' -Title 'No matching reports' `
                -Message 'No report matches the filters you selected. Try clearing the search or choosing different values.' `
                -Action '<a class="btn btn-outline" href="/complaints">Clear all filters</a>'
        }
        elseif ($isAdmin) {
            $rowsHtml = New-EmptyState -Icon '&#128203;' -Title 'No reports yet' `
                -Message 'Nobody has filed a complaint yet. When a resident submits one it will appear here.' `
                -Action '<a class="btn btn-primary" href="/complaints/new">File the first report</a>'
        }
        else {
            $rowsHtml = New-EmptyState -Icon '&#128221;' -Title 'You have not filed any reports yet' `
                -Message 'When you report a concern about your purok, it will appear here so you can follow its progress.' `
                -Action '<a class="btn btn-primary" href="/complaints/new">Report a concern</a>'
        }
    }

    # ---- summary chips ---------------------------------------------------
    $stats = Get-ComplaintStats -UserId $(if ($isAdmin) { '' } else { $user.id })
    $scopeNote = if ($isAdmin) { 'all residents' } else { 'filed by you' }

    $heading  = if ($isAdmin) { 'All complaints' } else { 'My reports' }
    $subtitle = if ($isAdmin) {
        'Every concern reported by residents of ' + $global:Config.BarangayName + '. Update the status as each one is acted on.'
    } else {
        'Every concern you have reported, newest first. You can edit or withdraw a report while it is still pending.'
    }

    $clearLink = ''
    if ($anyFilter) { $clearLink = '<a class="btn btn-ghost btn-sm" href="/complaints">Clear filters</a>' }

    $body = @"
<section class="container section">
  $(New-PageIntro -Eyebrow 'Complaint records' -Heading $heading -Sub $subtitle `
        -Actions ('<a class="btn btn-primary" href="/complaints/new">+ New report</a>' + $clearLink))

  $(New-FlashHtml $Ctx)

  <div class="stat-grid stat-grid-4">
    $(New-StatTile -Label ('Reports ' + $scopeNote) -Value $stats.Total    -Tone 'brand' -Hint 'Total on record')
    $(New-StatTile -Label 'Pending'      -Value $stats.Pending  -Tone 'warning' -Hint 'Awaiting first response')
    $(New-StatTile -Label 'In review'    -Value $stats.InReview -Tone 'info'    -Hint 'Being worked on now')
    $(New-StatTile -Label 'Resolved'     -Value $stats.Resolved -Tone 'success' -Hint 'Completed and closed')
  </div>

  <form class="filter-bar" method="get" action="/complaints" data-auto-submit>
    <div class="field field-inline">
      <label for="q">Search</label>
      <input type="search" id="q" name="q" placeholder="Reference number, title, location&hellip;"
             value="$(HtmlEncode $search)">
    </div>
    <div class="field field-inline">
      <label for="status">Status</label>
      <select id="status" name="status">$statusOptions</select>
    </div>
    <div class="field field-inline">
      <label for="category">Category</label>
      <select id="category" name="category">$categoryOptions</select>
    </div>
    <div class="field field-inline">
      <label for="priority">Priority</label>
      <select id="priority" name="priority">$priorityOptions</select>
    </div>
    <div class="filter-actions">
      <button class="btn btn-primary btn-sm" type="submit">Apply</button>
      <a class="btn btn-ghost btn-sm" href="/complaints">Reset</a>
    </div>
  </form>

  <p class="result-count">Showing <strong>$($visible.Count)</strong> of <strong>$total</strong> report(s)$(if ($anyFilter) { ' matching your filters' }).</p>

  <div class="row-list">$rowsHtml</div>

  $(New-Pagination -Page $page -TotalPages $totalPages -BaseUrl $baseUrl)
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title $heading -BodyHtml $body -ActiveNav 'complaints' -User $user -CsrfToken $csrf)
}

# --------------------------------------------------------------- READ one ---
function Invoke-ComplaintDetail {
    param($Ctx, [string]$Id)

    $user = $Ctx.Auth.User
    $csrf = Get-CsrfToken -Ctx $Ctx
    $item = Get-ComplaintById $Id

    if ($null -eq $item) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 404 -Heading 'Report not found' `
            -Message 'This report does not exist, or it may have been withdrawn by its reporter.' -User $user
        return
    }
    if (-not (Test-OwnsComplaint -Complaint $item -User $user)) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 403 -Heading 'This report is not yours' `
            -Message 'You can only open reports that you filed yourself. Administrators can view every report.' -User $user
        return
    }

    $isAdmin  = Test-IsAdmin $user
    $prioTone = Get-PriorityTone ([string]$item.priority)
    $statTone = Get-StatusTone ([string]$item.status)
    $base     = '/complaints/' + [System.Net.WebUtility]::UrlEncode([string]$item.id)

    $created = (Get-DateTimeFromIso ([string]$item.createdAt))
    $updated = (Get-DateTimeFromIso ([string]$item.updatedAt))

    $fields = @(
        @{ label = 'Reference number'; value = (HtmlEncode ([string]$item.referenceNo)) }
        @{ label = 'Category';          value = (HtmlEncode ([string]$item.category)) }
        @{ label = 'Location';          value = (HtmlEncode ([string]$item.location)) }
        @{ label = 'Date reported';     value = (HtmlEncode $created.ToString('dddd, dd MMMM yyyy')) }
        @{ label = 'Time reported';     value = (HtmlEncode $created.ToString('hh:mm tt')) }
        @{ label = 'Last updated';      value = (HtmlEncode $updated.ToString('dd MMM yyyy, hh:mm tt')) }
        @{ label = 'Reported by';       value = (HtmlEncode ([string]$item.reporterName)) }
        @{ label = 'Contact email';     value = '<a href="mailto:' + (HtmlEncode ([string]$item.reporterEmail)) + '">' + (HtmlEncode ([string]$item.reporterEmail)) + '</a>' }
    )
    $fieldsHtml = ''
    foreach ($f in $fields) {
        $fieldsHtml += '<div><dt>' + (HtmlEncode $f.label) + '</dt><dd>' + $f.value + '</dd></div>'
    }

    $notesHtml = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$item.adminNotes)) {
        $notesHtml = @"
<div class="admin-note">
  <p class="admin-note-label">Update from the Barangay</p>
  <p class="admin-note-text">$(HtmlEncode ([string]$item.adminNotes))</p>
</div>
"@
    }

    # Residents may still edit while pending; admins can always edit.
    $canEdit = $isAdmin -or ([string]$item.status -eq 'Pending')
    $editButton = ''
    if ($canEdit) {
        $editButton = '<a class="btn btn-outline" href="' + $base + '/edit">Edit report</a>'
    }

    $statusPanel = ''
    if ($isAdmin) {
        $statusPanel = New-AdminStatusPanelHtml -Complaint $item -Csrf $csrf -Base $base
    }

    $withdrawButton = @"
<a class="btn btn-danger-ghost" href="$base/delete" data-confirm-link="Remove this report permanently?">Delete report</a>
"@

    $timeline = New-TimelineHtml -Complaint $item

    $body = @"
<section class="container section">
  <nav class="breadcrumb" aria-label="Breadcrumb">
    <a href="/complaints">&larr; Back to reports</a>
  </nav>

  $(New-FlashHtml $Ctx)

  <div class="detail-layout">
    <article class="card detail-card">
      <div class="detail-head">
        <div class="row-badges">
          <span class="badge badge-$prioTone">$(HtmlEncode ([string]$item.priority)) priority</span>
          <span class="badge badge-$statTone">$(HtmlEncode ([string]$item.status))</span>
          <span class="badge badge-neutral">$(HtmlEncode ([string]$item.referenceNo))</span>
        </div>
        <h1 class="detail-title">$(HtmlEncode ([string]$item.title))</h1>
        <p class="detail-category">$(HtmlEncode ([string]$item.category))</p>
      </div>

      <div class="detail-body">
        <h2 class="detail-section-title">Description</h2>
        <p class="detail-text">$(HtmlEncode ([string]$item.description))</p>
        $notesHtml
      </div>

      <dl class="detail-list detail-list-grid">$fieldsHtml</dl>

      $timeline
    </article>

    <aside class="side-stack">
      $statusPanel
      <div class="card">
        <div class="card-head"><h2 class="card-title">Actions</h2></div>
        <div class="stack-actions">
          $editButton
          <a class="btn btn-ghost" href="/complaints/new">File another report</a>
          $withdrawButton
        </div>
        <p class="card-note">Deleting a report cannot be undone. You will be asked to confirm first.</p>
      </div>
      <div class="card card-quiet">
        <div class="card-head"><h2 class="card-title">Need help?</h2></div>
        <p class="card-text">Visit the Barangay Hall at $(HtmlEncode $global:Config.Address) or call the hotline at $(HtmlEncode $global:Config.Hotline).</p>
        <p class="card-text">Office hours: $(HtmlEncode $global:Config.OfficeHours).</p>
      </div>
    </aside>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title ([string]$item.title) -BodyHtml $body -ActiveNav 'complaints' -User $user -CsrfToken $csrf)
}

function New-AdminStatusPanelHtml {
    param($Complaint, [string]$Csrf, [string]$Base)

    $options = New-SelectOptions -Items $global:Statuses -Selected ([string]$Complaint.status)
    $notes   = HtmlEncode ([string]$Complaint.adminNotes)

    return @"
<div class="card card-status">
  <div class="card-head"><h2 class="card-title">Update status</h2></div>
  <form method="post" action="$Base/status" class="form-stack" novalidate>
    <input type="hidden" name="csrf_token" value="$Csrf">

    <div class="field">
      <label for="status">Current status</label>
      <select id="status" name="status">$options</select>
    </div>

    <div class="field">
      <label for="adminNotes">Note to the resident <span class="optional">optional</span></label>
      <textarea id="adminNotes" name="adminNotes" rows="4" maxlength="1000"
                placeholder="What action was taken?">$notes</textarea>
      <p class="field-hint">This note is visible to the resident who filed the report.</p>
    </div>

    <button class="btn btn-primary btn-block" type="submit">Save update</button>
  </form>
</div>
"@
}

function New-TimelineHtml {
    param($Complaint)

    $steps = @(
        @{ name = 'Pending';   hint = 'Report received' }
        @{ name = 'In Review'; hint = 'Being validated by the committee' }
        @{ name = 'Resolved';  hint = 'Action completed' }
    )
    $currentIndex = 2   # default when Resolved
    $status = [string]$Complaint.status
    if ($status -eq 'Pending')        { $currentIndex = 0 }
    elseif ($status -eq 'In Review') { $currentIndex = 1 }
    elseif ($status -eq 'Rejected')   { $currentIndex = 1 }

    $itemsHtml = ''
    for ($i = 0; $i -lt $steps.Count; $i++) {
        $state = 'pending'
        if ($i -lt $currentIndex) { $state = 'done' }
        elseif ($i -eq $currentIndex) { $state = 'current' }
        $label = HtmlEncode $steps[$i].name
        $hint  = HtmlEncode $steps[$i].hint
        $itemsHtml += '<li class="step step-' + $state + '"><span class="step-dot" aria-hidden="true"></span>' +
                      '<span class="step-body"><strong>' + $label + '</strong><small>' + $hint + '</small></span></li>'
    }

    $rejectedHtml = ''
    if ($status -eq 'Rejected') {
        $rejectedHtml = '<li class="step step-rejected"><span class="step-dot" aria-hidden="true"></span>' +
                        '<span class="step-body"><strong>Rejected</strong><small>Closed without action</small></span></li>'
    }

    return @"
<div class="detail-timeline">
  <h2 class="detail-section-title">Progress</h2>
  <ol class="steps">$itemsHtml</ol>
  $rejectedHtml
</div>
"@
}

# ---------------------------------------------------------------- CREATE ---
function Invoke-ComplaintForm {
    param($Ctx, [string]$Id = '')

    $user   = $Ctx.Auth.User
    $csrf   = Get-CsrfToken -Ctx $Ctx
    $errors = $Ctx.Errors
    $isEdit = -not [string]::IsNullOrWhiteSpace($Id)
    $item   = $null

    if ($isEdit) {
        $item = Get-ComplaintById $Id
        if ($null -eq $item) {
            Send-ErrorPage -Response $Ctx.Response -StatusCode 404 -Heading 'Report not found' `
                -Message 'This report no longer exists.' -User $user
            return
        }
        if (-not (Test-OwnsComplaint -Complaint $item -User $user)) {
            Send-ErrorPage -Response $Ctx.Response -StatusCode 403 -Heading 'This report is not yours' `
                -Message 'You can only edit reports that you filed yourself.' -User $user
            return
        }
        if (-not (Test-IsAdmin $user) -and [string]$item.status -ne 'Pending') {
            Send-ErrorPage -Response $Ctx.Response -StatusCode 403 -Heading 'This report can no longer be edited' `
                -Message 'Once the barangay starts reviewing a report it is locked so the record stays accurate. You can still add information by contacting the office.' -User $user
            return
        }
    }

    $values = @{
        title       = [string]$Ctx.FormData['title']
        category    = [string]$Ctx.FormData['category']
        priority    = [string]$Ctx.FormData['priority']
        location    = [string]$Ctx.FormData['location']
        description = [string]$Ctx.FormData['description']
        adminNotes  = [string]$Ctx.FormData['adminNotes']
    }

    if ($isEdit -and $errors.Count -eq 0 -and [string]::IsNullOrWhiteSpace([string]$values['title'])) {
        $values['title']       = [string]$item.title
        $values['category']    = [string]$item.category
        $values['priority']    = [string]$item.priority
        $values['location']    = [string]$item.location
        $values['description'] = [string]$item.description
        $values['adminNotes']  = [string]$item.adminNotes
    }

    $formAction = if ($isEdit) { '/complaints/' + [System.Net.WebUtility]::UrlEncode($item.id) + '/edit' } else { '/complaints/new' }
    $heading    = if ($isEdit) { 'Edit report' } else { 'Report a concern' }
    $sub        = if ($isEdit) {
        'Correct the details of your report. Your reference number and the date you filed it stay the same.'
    } else {
        'Tell us what is wrong and where. Fields marked with * are required.'
    }
    $submit     = if ($isEdit) { 'Save changes' } else { 'Submit report' }

    $categoryOptions = New-SelectOptions -Items $global:Categories -Selected $values['category']
    $priorityOptions = New-SelectOptions -Items $global:Priorities -Selected $values['priority']

    $categoryHints = ''
    foreach ($c in $global:Categories) {
        $categoryHints += '<li><strong>' + (HtmlEncode $c.Value) + '</strong> &mdash; ' + (HtmlEncode $c.Hint) + '</li>'
    }
    $priorityHints = ''
    foreach ($p in $global:Priorities) {
        $priorityHints += '<li><strong>' + (HtmlEncode $p.Value) + '</strong> &mdash; ' + (HtmlEncode $p.Hint) + '</li>'
    }

    $notesField = ''
    if (Test-IsAdmin $user) {
        $notesField = @"
<div class="field">
  <label for="adminNotes">Internal note <span class="optional">optional</span></label>
  <textarea id="adminNotes" name="adminNotes" rows="3" maxlength="1000"
            placeholder="Actions taken, referrals, follow-up schedule">$(HtmlEncode $values['adminNotes'])</textarea>
</div>
"@
    }

    $body = @"
<section class="container section-narrow">
  <nav class="breadcrumb" aria-label="Breadcrumb">
    <a href="/complaints">&larr; Back to reports</a>
  </nav>

  $(New-PageIntro -Eyebrow 'Complaint form' -Heading $heading -Sub $sub)

  $(New-FlashHtml $Ctx)
  $(New-ErrorSummary $errors)

  <div class="form-layout">
    <div class="card">
      <form method="post" action="$formAction" class="form-stack" novalidate>
        <input type="hidden" name="csrf_token" value="$(HtmlEncode $csrf)">

        <div class="field">
          <label for="title">Short title <span class="req" aria-hidden="true">*</span></label>
          <input type="text" id="title" name="title" maxlength="120" required
                 placeholder="Example: Deep pothole in front of Barangay Hall"
                 value="$(HtmlEncode $values['title'])"$(Get-FieldInvalidClass $errors 'title')>
          <p class="field-hint">In one line: what is the problem?</p>
          $(New-FieldErrorHtml $errors 'title')
        </div>

        <div class="field-grid">
          <div class="field">
            <label for="category">Category <span class="req" aria-hidden="true">*</span></label>
            <select id="category" name="category" required$(Get-FieldInvalidClass $errors 'category')>
              <option value="">-- Choose a category --</option>$categoryOptions
            </select>
            $(New-FieldErrorHtml $errors 'category')
          </div>

          <div class="field">
            <label for="priority">How urgent is it? <span class="req" aria-hidden="true">*</span></label>
            <select id="priority" name="priority" required$(Get-FieldInvalidClass $errors 'priority')>
              <option value="">-- Choose a priority --</option>$priorityOptions
            </select>
            $(New-FieldErrorHtml $errors 'priority')
          </div>
        </div>

        <div class="field">
          <label for="location">Exact location <span class="req" aria-hidden="true">*</span></label>
          <input type="text" id="location" name="location" maxlength="140" required
                 placeholder="Example: Purok 5, corner of Mabini Street"
                 value="$(HtmlEncode $values['location'])"$(Get-FieldInvalidClass $errors 'location')>
          <p class="field-hint">Give the purok, street or nearest landmark so the crew can find it.</p>
          $(New-FieldErrorHtml $errors 'location')
        </div>

        <div class="field">
          <label for="description">Full description <span class="req" aria-hidden="true">*</span></label>
          <textarea id="description" name="description" rows="7" maxlength="2000" required
                    placeholder="Describe what happened, how long it has been a problem, and who is affected."
                    data-char-count data-char-max="2000"$(Get-FieldInvalidClass $errors 'description')
          >$(HtmlEncode $values['description'])</textarea>
          <p class="field-hint char-count"><span data-char-current>0</span> / 2,000 characters</p>
          $(New-FieldErrorHtml $errors 'description')
        </div>

        $notesField

        <div class="reporter-preview">
          <p class="reporter-label">This report will be filed under</p>
          <p class="reporter-name">$(HtmlEncode $user.name)</p>
          <p class="reporter-meta">$(HtmlEncode $user.email) &middot; $(HtmlEncode $user.address)</p>
        </div>

        <div class="form-actions">
          <button class="btn btn-primary" type="submit">$(HtmlEncode $submit)</button>
          <a class="btn btn-ghost" href="/complaints">Cancel</a>
        </div>
      </form>
    </div>

    <aside class="side-stack">
      <div class="card card-quiet">
        <div class="card-head"><h2 class="card-title">What happens next?</h2></div>
        <ol class="mini-steps">
          <li>You get a reference number such as <code>BCR-2026-0001</code>.</li>
          <li>The barangay reviews your report and sets a status.</li>
          <li>You can check the status and read notes any time from your dashboard.</li>
          <li>When the work is done the status becomes <strong>Resolved</strong>.</li>
        </ol>
      </div>

      <div class="card card-quiet">
        <div class="card-head"><h2 class="card-title">Categories</h2></div>
        <ul class="hint-list">$categoryHints</ul>
      </div>

      <div class="card card-quiet">
        <div class="card-head"><h2 class="card-title">Priority guide</h2></div>
        <ul class="hint-list">$priorityHints</ul>
      </div>
    </aside>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title $heading -BodyHtml $body -ActiveNav 'new' -User $user -CsrfToken $csrf)
}

function Invoke-ComplaintCreate {
    param($Ctx)

    $user = $Ctx.Auth.User
    if (-not (Test-CsrfToken -Ctx $Ctx)) {
        Send-Html -Response $Ctx.Response -StatusCode 400 -Html (New-HtmlDocument `
            -Title 'Invalid request' -User $user -CsrfToken (Get-CsrfToken $Ctx) `
            -BodyHtml (New-ErrorBody -StatusCode 400 -Heading 'That request could not be verified' `
                -Message 'Your form failed its security check. Please go back and submit it again.'))
        return
    }

    $result = Validate-ComplaintInput -Body $Ctx.Body
    $values = $result.Values
    $errors = $result.Errors

    if ($errors.Count -gt 0) {
        $Ctx.Errors   = $errors
        $Ctx.FormData = $values
        Invoke-ComplaintForm -Ctx $Ctx
        return
    }

    $record = [pscustomobject]@{
        id            = (New-Id 'cmp')
        referenceNo   = (New-ComplaintReference)
        title         = $values['title']
        description   = $values['description']
        category      = $values['category']
        priority      = $values['priority']
        status        = 'Pending'
        location      = $values['location']
        reporterId    = [string]$user.id
        reporterName  = [string]$user.name
        reporterEmail = [string]$user.email
        reporterPhone = [string]$user.phone
        adminNotes    = [string]$(if ($values.ContainsKey('adminNotes')) { $values['adminNotes'] } else { '' })
        createdAt     = (Get-NowIso)
        updatedAt     = (Get-NowIso)
        updatedBy     = [string]$user.id
    }

    $null = Save-Complaint $record
    Write-AuditLog -Ctx $Ctx -Action 'complaint_create' -Detail ('Created ' + $record.referenceNo + ': ' + $record.title)

    if (Test-IsAdmin $user) {
        Send-Redirect -Response $Ctx.Response -Location `
            (Get-FlashUrl ('/complaints/' + $record.id) 'created' @{ ref = $record.referenceNo })
    } else {
        Send-Redirect -Response $Ctx.Response -Location `
            (Get-FlashUrl '/dashboard' 'created' @{ ref = $record.referenceNo })
    }
}

# ----------------------------------------------------------------- UPDATE ---
function Invoke-ComplaintUpdate {
    param($Ctx, [string]$Id)

    $user = $Ctx.Auth.User
    if (-not (Test-CsrfToken -Ctx $Ctx)) {
        Send-Html -Response $Ctx.Response -StatusCode 400 -Html (New-HtmlDocument `
            -Title 'Invalid request' -User $user -CsrfToken (Get-CsrfToken $Ctx) `
            -BodyHtml (New-ErrorBody -StatusCode 400 -Heading 'That request could not be verified' `
                -Message 'Your form failed its security check. Please go back and submit it again.'))
        return
    }

    $item = Get-ComplaintById $Id
    if ($null -eq $item) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 404 -Heading 'Report not found' `
            -Message 'This report no longer exists.' -User $user
        return
    }
    if (-not (Test-OwnsComplaint -Complaint $item -User $user)) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 403 -Heading 'This report is not yours' `
            -Message 'You can only edit reports that you filed yourself.' -User $user
        return
    }
    if (-not (Test-IsAdmin $user) -and [string]$item.status -ne 'Pending') {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 403 -Heading 'This report can no longer be edited' `
            -Message 'Only reports that are still Pending can be edited by the resident who filed them.' -User $user
        return
    }

    $result = Validate-ComplaintInput -Body $Ctx.Body
    $values = $result.Values
    $errors = $result.Errors

    if ($errors.Count -gt 0) {
        $Ctx.Errors   = $errors
        $Ctx.FormData = $values
        Invoke-ComplaintForm -Ctx $Ctx -Id $Id
        return
    }

    $item | Add-Member -NotePropertyName 'title'       -NotePropertyValue $values['title']       -Force
    $item | Add-Member -NotePropertyName 'description' -NotePropertyValue $values['description'] -Force
    $item | Add-Member -NotePropertyName 'category'    -NotePropertyValue $values['category']    -Force
    $item | Add-Member -NotePropertyName 'priority'    -NotePropertyValue $values['priority']    -Force
    $item | Add-Member -NotePropertyName 'location'    -NotePropertyValue $values['location']    -Force
    $item | Add-Member -NotePropertyName 'updatedAt'   -NotePropertyValue (Get-NowIso)            -Force
    $item | Add-Member -NotePropertyName 'updatedBy'   -NotePropertyValue ([string]$user.id)       -Force

    if (Test-IsAdmin $user) {
        $notes = [string]$(if ($values.ContainsKey('adminNotes')) { $values['adminNotes'] } else { '' })
        $item | Add-Member -NotePropertyName 'adminNotes' -NotePropertyValue $notes -Force
    }

    $null = Save-Complaint $item
    Write-AuditLog -Ctx $Ctx -Action 'complaint_update' -Detail ('Updated ' + $item.referenceNo)

    $Ctx.Flash = @{ type = 'success'; message = ('Report ' + $item.referenceNo + ' has been updated.') }
    Invoke-ComplaintDetail -Ctx $Ctx -Id $Id
}

function Invoke-ComplaintStatusUpdate {
    param($Ctx, [string]$Id)

    $user = $Ctx.Auth.User
    if (-not (Test-IsAdmin $user)) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 403 -Heading 'Administrator access only' `
            -Message 'Only barangay administrators can change the status of a report.' -User $user
        return
    }
    if (-not (Test-CsrfToken -Ctx $Ctx)) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 400 -Heading 'That request could not be verified' `
            -Message 'Your form failed its security check. Please go back and try again.' -User $user
        return
    }

    $item = Get-ComplaintById $Id
    if ($null -eq $item) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 404 -Heading 'Report not found' `
            -Message 'This report no longer exists.' -User $user
        return
    }

    $newStatus = Get-FormValue -Body $Ctx.Body -Name 'status'
    if ($global:Statuses.Value -notcontains $newStatus) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 400 -Heading 'Invalid status' `
            -Message 'Please choose a status from the list provided.' -User $user
        return
    }

    $notes = Get-FormValue -Body $Ctx.Body -Name 'adminNotes'
    if ($notes.Length -gt 1000) {
        $notes = $notes.Substring(0, 1000)
    }

    $oldStatus = [string]$item.status
    $item | Add-Member -NotePropertyName 'status'     -NotePropertyValue $newStatus -Force
    $item | Add-Member -NotePropertyName 'adminNotes' -NotePropertyValue $notes    -Force
    $item | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue (Get-NowIso) -Force
    $item | Add-Member -NotePropertyName 'updatedBy' -NotePropertyValue ([string]$user.id) -Force
    $null = Save-Complaint $item

    Write-AuditLog -Ctx $Ctx -Action 'complaint_status' `
        -Detail ($item.referenceNo + ': ' + $oldStatus + ' -> ' + $newStatus)

    Send-Redirect -Response $Ctx.Response -Location `
        (Get-FlashUrl ('/complaints/' + $item.id) 'statuschanged' @{ ref = $item.referenceNo; status = $newStatus })
}

# ----------------------------------------------------------------- DELETE ---
function Invoke-ComplaintDeleteConfirm {
    param($Ctx, [string]$Id)

    $user = $Ctx.Auth.User
    $csrf = Get-CsrfToken -Ctx $Ctx
    $item = Get-ComplaintById $Id

    if ($null -eq $item) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 404 -Heading 'Report not found' `
            -Message 'This report has already been removed.' -User $user
        return
    }
    if (-not (Test-OwnsComplaint -Complaint $item -User $user)) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 403 -Heading 'This report is not yours' `
            -Message 'You can only delete reports that you filed yourself.' -User $user
        return
    }

    $isAdmin = Test-IsAdmin $user
    $who     = if ($isAdmin) { 'This will remove the report permanently for the resident as well.' }
               else { 'This report will be removed from the barangay records as well.' }

    $body = @"
<section class="container section-narrow">
  <nav class="breadcrumb" aria-label="Breadcrumb">
    <a href="/complaints/$(HtmlEncode ([System.Net.WebUtility]::UrlEncode([string]$item.id)))">&larr; Back to report</a>
  </nav>

  $(New-PageIntro -Eyebrow 'Confirm deletion' -Heading 'Delete this report?' -Sub $who)

  $(New-FlashHtml $Ctx)

  <div class="card card-danger">
    <div class="danger-head">
      <span class="danger-icon" aria-hidden="true">&#128465;</span>
      <div>
        <h2 class="danger-title">This action cannot be undone</h2>
        <p class="danger-text">Please review the details below before you continue.</p>
      </div>
    </div>

    <dl class="detail-list">
      <div><dt>Reference number</dt><dd>$(HtmlEncode ([string]$item.referenceNo))</dd></div>
      <div><dt>Title</dt><dd>$(HtmlEncode ([string]$item.title))</dd></div>
      <div><dt>Category</dt><dd>$(HtmlEncode ([string]$item.category))</dd></div>
      <div><dt>Location</dt><dd>$(HtmlEncode ([string]$item.location))</dd></div>
      <div><dt>Status</dt><dd>$(HtmlEncode ([string]$item.status))</dd></div>
      <div><dt>Reported on</dt><dd>$(HtmlEncode ((Get-DateTimeFromIso ([string]$item.createdAt)).ToString('dd MMMM yyyy, yyyy')))</dd></div>
    </dl>

    <div class="form-actions form-actions-split">
      <form method="post" action="/complaints/$(HtmlEncode ([System.Net.WebUtility]::UrlEncode([string]$item.id)))/delete" class="inline-form">
        <input type="hidden" name="csrf_token" value="$(HtmlEncode $csrf)">
        <input type="hidden" name="confirm" value="yes">
        <button class="btn btn-danger" type="submit">Yes, delete this report</button>
      </form>
      <a class="btn btn-ghost" href="/complaints/$(HtmlEncode ([System.Net.WebUtility]::UrlEncode([string]$item.id)))">Cancel, keep the report</a>
    </div>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title 'Confirm deletion' -BodyHtml $body -ActiveNav 'complaints' -User $user -CsrfToken $csrf)
}

function Invoke-ComplaintDelete {
    param($Ctx, [string]$Id)

    $user = $Ctx.Auth.User
    $item = Get-ComplaintById $Id

    if ($null -eq $item) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 404 -Heading 'Report not found' `
            -Message 'This report has already been removed.' -User $user
        return
    }
    if (-not (Test-OwnsComplaint -Complaint $item -User $user)) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 403 -Heading 'This report is not yours' `
            -Message 'You can only delete reports that you filed yourself.' -User $user
        return
    }
    if (-not (Test-CsrfToken -Ctx $Ctx)) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 400 -Heading 'That request could not be verified' `
            -Message 'Your form failed its security check. Please go back and try again.' -User $user
        return
    }

    # The confirm page posts an explicit confirmation flag; refuse otherwise.
    $confirm = Get-FormValue -Body $Ctx.Body -Name 'confirm'
    if ($confirm -ne 'yes') {
        Send-Redirect -Response $Ctx.Response -Location ('/complaints/' + [System.Net.WebUtility]::UrlEncode([string]$item.id) + '/delete')
        return
    }

    $reference = [string]$item.referenceNo
    $title     = [string]$item.title
    Remove-ComplaintRecord -Id $item.id
    Write-AuditLog -Ctx $Ctx -Action 'complaint_delete' -Detail ('Deleted ' + $reference + ': ' + $title)

    Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/complaints' 'deleted' @{ ref = $reference })
}
