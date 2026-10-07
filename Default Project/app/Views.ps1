# ============================================================================
#  Views.ps1 - HTML shell, layout and reusable UI components
#  All dynamic values pass through HtmlEncode before reaching the page.
# ============================================================================

function Get-RehydratedValue {
    <#
        Returns the HTML-encoded value the user typed previously so a rejected
        form can be re-rendered without making them retype everything.
    #>
    param($FormData, [string]$Key, [string]$Default = '')
    if ($null -ne $FormData -and $FormData.ContainsKey($Key)) {
        $raw = [string]$FormData[$Key]
        if (-not [string]::IsNullOrWhiteSpace($raw)) { return (HtmlEncode $raw) }
    }
    return $Default
}

function Get-PriorityTone {
    param([string]$Priority)
    switch ($Priority) {
        'Urgent' { return 'danger' }
        'High'   { return 'warning' }
        'Medium' { return 'info' }
        default  { return 'neutral' }
    }
}

function Get-StatusTone {
    param([string]$Status)
    switch ($Status) {
        'Resolved'  { return 'success' }
        'In Review' { return 'info' }
        'Rejected'  { return 'muted' }
        default     { return 'warning' }
    }
}

function Get-InitialsBadges {
    param([object]$User)
    if ($null -eq $User) { return '' }
    $tone = if (Test-IsAdmin $User) { 'badge-admin' } else { 'badge-resident' }
    return '<span class="avatar ' + $tone + '">' + (HtmlEncode (Get-Initials $User.name)) + '</span>'
}

# ------------------------------------------------------------------- shell --
function New-HtmlDocument {
    param(
        [string]$Title,
        [string]$BodyHtml,
        [object]$User = $null,
        [string]$ActiveNav = '',
        [string]$CsrfToken = '',
        [switch]$Wide
    )

    $siteName = $global:Config.SiteName
    $barangay = $global:Config.BarangayName
    $fullTitle = if ([string]::IsNullOrWhiteSpace($Title)) { $siteName } else { "$Title - $barangay" }

    $navHtml = New-NavBarHtml -User $User -Active $ActiveNav
    $footHtml = New-FooterHtml

    $bodyClass = if ($Wide) { 'page page-wide' } else { 'page' }

    $document = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Report concerns about your barangay online - roads, water, electricity, waste, noise, health and safety. Track every report from Pending to Resolved.">
<meta name="theme-color" content="#0b3d2e">
<title>$(HtmlEncode $fullTitle)</title>
<link rel="icon" type="image/svg+xml" href="/img/favicon.svg">
<link rel="stylesheet" href="/css/style.css">
</head>
<body class="$bodyClass">

<a class="skip-link" href="#main-content">Skip to main content</a>

$navHtml

<main id="main-content" class="main">
$BodyHtml
</main>

$footHtml

<script src="/js/app.js" defer></script>
</body>
</html>
"@

    # Every state-changing form ships the per-session CSRF token.
    if ([string]::IsNullOrWhiteSpace($CsrfToken)) { $CsrfToken = '' }
    return $document.Replace('__CSRF__', [System.Net.WebUtility]::HtmlEncode($CsrfToken))
}

function New-NavBarHtml {
    param([object]$User = $null, [string]$Active = '')

    $barangay = HtmlEncode $global:Config.BarangayName

    if ($null -eq $User) {
        $links = @(
            @{ href = '/';              label = 'Home';            key = 'home' }
            @{ href = '/#services';     label = 'Services';       key = 'services' }
            @{ href = '/#how-it-works'; label = 'How It Works';   key = 'how' }
            @{ href = '/#faq';          label = 'FAQ';            key = 'faq' }
        )
        $navHtml = ''
        foreach ($l in $links) {
            $cls = if ($Active -eq $l.key) { ' class="is-active"' } else { '' }
            $navHtml += '<a href="' + $l.href + '"' + $cls + '>' + (HtmlEncode $l.label) + '</a>'
        }

        $actions = @'
<a class="btn btn-ghost" href="/login">Sign in</a>
<a class="btn btn-primary" href="/register">Create account</a>
'@
        $identity = ''
        $menuButtonClass = 'nav-toggle'
    }
    else {
        $links = @(
            @{ href = '/dashboard';  label = 'Dashboard';  key = 'dashboard' }
        )
        if (Test-IsAdmin $User) {
            $links += @{ href = '/complaints'; label = 'All Reports'; key = 'complaints' }
            $links += @{ href = '/users';       label = 'Residents';  key = 'users' }
        } else {
            $links += @{ href = '/complaints'; label = 'My Reports'; key = 'complaints' }
        }
        $links += @{ href = '/complaints/new'; label = 'New Report'; key = 'new' }

        $navHtml = ''
        foreach ($l in $links) {
            $cls = if ($Active -eq $l.key) { ' class="is-active"' } else { '' }
            $navHtml += '<a href="' + $l.href + '"' + $cls + '>' + (HtmlEncode $l.label) + '</a>'
        }

        $roleLabel = if (Test-IsAdmin $User) { 'Administrator' } else { 'Resident' }
        $roleTone  = if (Test-IsAdmin $User) { 'role-admin' } else { 'role-resident' }
        $identity = @"
<div class="user-chip">
  $(Get-InitialsBadges $User)
  <span class="user-chip-text">
    <strong>$(HtmlEncode $User.name)</strong>
    <span class="role-pill $roleTone">$roleLabel</span>
  </span>
</div>
<form method="post" action="/logout" class="inline-form">
  <input type="hidden" name="csrf_token" value="__CSRF__">
  <button class="btn btn-ghost btn-sm" type="submit">Sign out</button>
</form>
"@
        $actions = ''
        $menuButtonClass = 'nav-toggle nav-toggle-signed-in'
    }

    return @"
<header class="site-header" id="siteHeader">
  <div class="container header-inner">
    <a class="brand" href="/">
      <img class="brand-mark" src="/img/logo.svg" width="44" height="44" alt="Barangay seal logo">
      <span class="brand-text">
        <strong>$barangay</strong>
        <small>Complaint &amp; Concern Reporting</small>
      </span>
    </a>

    <button class="$menuButtonClass" type="button" data-nav-toggle aria-expanded="false" aria-controls="siteNav" aria-label="Toggle navigation menu">
      <span class="nav-toggle-bars" aria-hidden="true"><span></span><span></span><span></span></span>
      <span class="nav-toggle-text">Menu</span>
    </button>

    <nav class="site-nav" id="siteNav" data-nav-panel aria-label="Main navigation">
      <div class="nav-links">$navHtml</div>
      <div class="nav-actions">
        $actions
        $identity
      </div>
    </nav>
  </div>
</header>
"@
}

function New-FooterHtml {
    $barangay    = HtmlEncode $global:Config.BarangayName
    $municipality = HtmlEncode $global:Config.Municipality
    $address     = HtmlEncode $global:Config.Address
    $hotline     = HtmlEncode $global:Config.Hotline
    $email       = HtmlEncode $global:Config.Email
    $hours       = HtmlEncode $global:Config.OfficeHours
    $year        = (Get-Date).Year

    $cats = ''
    foreach ($c in $global:Categories[0..3]) {
        $cats += '<li>' + (HtmlEncode $c.Value) + '</li>'
    }

    return @"
<footer class="site-footer">
  <div class="container footer-grid">
    <div class="footer-brand">
      <img class="brand-mark" src="/img/logo.svg" width="52" height="52" alt="">
      <p class="footer-name">$barangay</p>
      <p class="footer-tagline">Complaint and Concern Reporting System &middot; $municipality</p>
      <p class="footer-tagline">A digital channel for faster, more transparent community action.</p>
    </div>

    <div class="footer-col">
      <h3>What you can report</h3>
      <ul class="footer-list">$cats</ul>
      <ul class="footer-list">
        <li><a href="/complaints/new">Submit a report</a></li>
        <li><a href="/complaints">Track a report</a></li>
      </ul>
    </div>

    <div class="footer-col">
      <h3>Barangay office</h3>
      <ul class="footer-list">
        <li>$address</li>
        <li>Hotline: $hotline</li>
        <li><a href="mailto:$email">$email</a></li>
        <li>$hours</li>
      </ul>
    </div>

    <div class="footer-col">
      <h3>Account</h3>
      <ul class="footer-list">
        <li><a href="/register">Create an account</a></li>
        <li><a href="/login">Sign in</a></li>
        <li><a href="/#faq">Frequently asked questions</a></li>
      </ul>
    </div>
  </div>

  <div class="container footer-bottom">
    <p>&copy; $year $barangay. All rights reserved.</p>
    <p class="footer-privacy">Your reports are visible only to you and to authorized barangay administrators.</p>
  </div>
</footer>
"@
}

# --------------------------------------------------------------- components --
function Get-ResolvedFlash {
    <#
        Flash messages can arrive two ways:
          1. $Ctx.Flash  - set during the current request (a form was rejected,
             or a handler re-rendered the page after a successful save).
          2. ?ok=<key>   - set by Get-FlashUrl before a redirect, so the message
             survives the extra HTTP round trip.
    #>
    param($Ctx)

    if ($null -ne $Ctx.Flash) {
        if ($Ctx.Flash -is [hashtable]) { return $Ctx.Flash }
        return @{ type = 'success'; message = [string]$Ctx.Flash }
    }

    $key = Get-QueryValue -Request $Ctx.Request -Name 'ok'
    if ([string]::IsNullOrWhiteSpace($key)) { return $null }
    if (-not $global:FlashMessages.ContainsKey($key)) { return $null }

    $entry   = $global:FlashMessages[$key]
    $message = [string]$entry['message']
    foreach ($field in @('ref', 'name', 'email', 'count', 'status', 'role')) {
        $message = $message.Replace('{' + $field + '}',
            (Get-QueryValue -Request $Ctx.Request -Name $field))
    }
    return @{ type = [string]$entry['type']; message = $message }
}

function New-FlashHtml {
    param($Ctx)

    $flash = Get-ResolvedFlash -Ctx $Ctx
    if ($null -eq $flash) { return '' }

    $tone    = [string]$flash['type']
    $message = [string]$flash['message']
    if ([string]::IsNullOrWhiteSpace($tone)) { $tone = 'info' }

    $icons = @{ success = '&#10003;'; error = '&#33;'; warning = '&#9888;'; info = '&#8505;' }
    $icon  = $icons[$tone]
    if ($null -eq $icon) { $icon = '&#8505;' }
    $dismiss = ''
    if ($tone -eq 'success') {
        $dismiss = '<button class="flash-close" type="button" data-dismiss-flash aria-label="Dismiss message">&times;</button>'
    }
    return '<div class="flash flash-' + $tone + '" role="status" data-flash>' +
           '<span class="flash-icon" aria-hidden="true">' + $icon + '</span>' +
           '<p class="flash-text">' + (HtmlEncode $message) + '</p>' + $dismiss + '</div>'
}

function New-ErrorSummary {
    param([hashtable]$Errors)
    if ($null -eq $Errors -or $Errors.Count -eq 0) { return '' }
    $items = ''
    foreach ($k in $Errors.Keys) {
        $items += '<li>' + (HtmlEncode $Errors[$k]) + '</li>'
    }
    return @"
<div class="alert alert-error" role="alert">
  <span class="alert-icon" aria-hidden="true">&#9888;</span>
  <div>
    <strong>Please fix the following before continuing:</strong>
    <ul class="alert-list">$items</ul>
  </div>
</div>
"@
}

function New-FieldErrorHtml {
    param([hashtable]$Errors, [string]$Field)
    if ($null -eq $Errors -or -not $Errors.ContainsKey($Field)) { return '' }
    return '<p class="field-error" data-field-error="' + (HtmlEncode $Field) + '">' + (HtmlEncode $Errors[$Field]) + '</p>'
}

function Get-FieldInvalidClass {
    param([hashtable]$Errors, [string]$Field)
    if ($null -ne $Errors -and $Errors.ContainsKey($Field)) { return ' is-invalid' }
    return ''
}

function New-PageIntro {
    param([string]$Eyebrow, [string]$Heading, [string]$Sub = '', [string]$Actions = '')

    $eyebrowHtml = ''
    if (-not [string]::IsNullOrWhiteSpace($Eyebrow)) {
        $eyebrowHtml = '<p class="page-eyebrow">' + (HtmlEncode $Eyebrow) + '</p>'
    }
    $subHtml = ''
    if (-not [string]::IsNullOrWhiteSpace($Sub)) {
        $subHtml = '<p class="page-sub">' + (HtmlEncode $Sub) + '</p>'
    }
    $actionsHtml = ''
    if (-not [string]::IsNullOrWhiteSpace($Actions)) {
        $actionsHtml = '<div class="page-actions">' + $Actions + '</div>'
    }

    return '<div class="page-intro">' + $eyebrowHtml +
           '<h1 class="page-title">' + (HtmlEncode $Heading) + '</h1>' +
           $subHtml + $actionsHtml + '</div>'
}

function New-SectionHeading {
    param([string]$Eyebrow, [string]$Heading, [string]$Sub = '', [string]$Align = 'left')
    $alignClass = 'section-head section-head-' + $Align
    $out = '<div class="' + $alignClass + '">'
    if (-not [string]::IsNullOrWhiteSpace($Eyebrow)) {
        $out += '<p class="section-eyebrow">' + (HtmlEncode $Eyebrow) + '</p>'
    }
    $out += '<h2 class="section-title">' + (HtmlEncode $Heading) + '</h2>'
    if (-not [string]::IsNullOrWhiteSpace($Sub)) {
        $out += '<p class="section-sub">' + (HtmlEncode $Sub) + '</p>'
    }
    $out += '</div>'
    return $out
}

function New-SelectOptions {
    param([array]$Items, [string]$Selected)
    $html = ''
    foreach ($item in $Items) {
        $isSelected = if ([string]$item.Value -eq [string]$Selected) { ' selected' } else { '' }
        $html += '<option value="' + (HtmlEncode $item.Value) + '"' + $isSelected + '>' + (HtmlEncode $item.Value) + '</option>'
    }
    return $html
}

function New-ComplaintRow {
    param($Complaint, [object]$Viewer, [switch]$Compact)

    $isAdmin  = Test-IsAdmin $Viewer
    $prioTone = Get-PriorityTone ([string]$Complaint.priority)
    $statTone = Get-StatusTone ([string]$Complaint.status)
    $ref      = HtmlEncode ([string]$Complaint.referenceNo)
    $title    = HtmlEncode ([string]$Complaint.title)
    $cat      = HtmlEncode ([string]$Complaint.category)
    $loc      = HtmlEncode ([string]$Complaint.location)
    $created  = HtmlEncode ((Get-DateTimeFromIso ([string]$Complaint.createdAt)).ToString('dd MMM yyyy'))
    $name     = HtmlEncode ([string]$Complaint.reporterName)

    $meta = @(
        '<span class="meta-item"><span class="meta-label">Reference</span> ' + $ref + '</span>'
        '<span class="meta-item"><span class="meta-label">Category</span> ' + $cat + '</span>'
        '<span class="meta-item"><span class="meta-label">Location</span> ' + $loc + '</span>'
        '<span class="meta-item"><span class="meta-label">Reported</span> ' + $created + '</span>'
    ) -join ''

    $reporterHtml = ''
    if ($isAdmin) {
        $reporterHtml = '<span class="meta-item"><span class="meta-label">Reported by</span> ' + $name + '</span>'
    }

    $descHtml = ''
    if (-not $Compact) {
        $desc = [string]$Complaint.description
        if ($desc.Length -gt 190) { $desc = $desc.Substring(0, 190).TrimEnd() + '&hellip;' }
        $descHtml = '<p class="row-desc">' + (HtmlEncode ([System.Net.WebUtility]::HtmlDecode($desc))) + '</p>'
    }

    $notesHtml = ''
    $notes = [string]$Complaint.adminNotes
    if ($isAdmin -and -not [string]::IsNullOrWhiteSpace($notes)) {
        $short = $notes
        if ($short.Length -gt 120) { $short = $short.Substring(0, 120).TrimEnd() + '&hellip;' }
        $notesHtml = '<p class="row-note"><span class="meta-label">Admin note</span> ' +
                     (HtmlEncode ([System.Net.WebUtility]::HtmlDecode($short))) + '</p>'
    }

    $actionPath = '/complaints/' + [System.Net.WebUtility]::UrlEncode([string]$Complaint.id)

    return @"
<article class="row-card" data-complaint-row data-priority="$prioTone" data-status="$statTone">
  <div class="row-main">
    <div class="row-badges">
      <span class="badge badge-$prioTone">$(HtmlEncode ([string]$Complaint.priority))</span>
      <span class="badge badge-$statTone">$(HtmlEncode ([string]$Complaint.status))</span>
    </div>
    <h3 class="row-title"><a href="$actionPath">$title</a></h3>
    <div class="row-meta">$meta $reporterHtml</div>
    $descHtml
    $notesHtml
  </div>
  <div class="row-side">
    <a class="btn btn-outline btn-sm" href="$actionPath">View details</a>
  </div>
</article>
"@
}

function New-StatTile {
    param([string]$Label, $Value, [string]$Tone = 'brand', [string]$Hint = '')
    $hintHtml = ''
    if (-not [string]::IsNullOrWhiteSpace($Hint)) {
        $hintHtml = '<p class="stat-hint">' + (HtmlEncode $Hint) + '</p>'
    }
    return @"
<div class="stat-tile stat-$Tone">
  <p class="stat-value">$Value</p>
  <p class="stat-label">$(HtmlEncode $Label)</p>
  $hintHtml
</div>
"@
}

function New-EmptyState {
    param([string]$Title, [string]$Message, [string]$Action = '', [string]$Icon = '&#128196;')
    $actionHtml = ''
    if (-not [string]::IsNullOrWhiteSpace($Action)) { $actionHtml = '<div class="empty-action">' + $Action + '</div>' }
    return @"
<div class="empty-state">
  <span class="empty-icon" aria-hidden="true">$Icon</span>
  <h3 class="empty-title">$(HtmlEncode $Title)</h3>
  <p class="empty-text">$(HtmlEncode $Message)</p>
  $actionHtml
</div>
"@
}

function New-Pagination {
    param([int]$Page, [int]$TotalPages, [string]$BaseUrl)

    if ($TotalPages -le 1) { return '' }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('<nav class="pagination" aria-label="Pagination"><ul>')

    $prevDisabled = if ($Page -le 1) { ' is-disabled' } else { '' }
    $prevHref = if ($Page -le 1) { '#' } else { $BaseUrl + '&page=' + ($Page - 1) }
    [void]$sb.Append('<li class="page-item' + $prevDisabled + '"><a href="' + $prevHref + '" rel="prev">&larr; Previous</a></li>')

    for ($i = 1; $i -le $TotalPages; $i++) {
        if ($i -eq $Page) {
            [void]$sb.Append('<li class="page-item is-current"><span aria-current="page">' + $i + '</span></li>')
        } else {
            [void]$sb.Append('<li class="page-item"><a href="' + $BaseUrl + '&page=' + $i + '">' + $i + '</a></li>')
        }
    }

    $nextDisabled = if ($Page -ge $TotalPages) { ' is-disabled' } else { '' }
    $nextHref = if ($Page -ge $TotalPages) { '#' } else { $BaseUrl + '&page=' + ($Page + 1) }
    [void]$sb.Append('<li class="page-item' + $nextDisabled + '"><a href="' + $nextHref + '" rel="next">Next &rarr;</a></li>')

    [void]$sb.Append('</ul></nav>')
    return $sb.ToString()
}

function New-ErrorBody {
    param([int]$StatusCode, [string]$Heading, [string]$Message)

    $icon = '&#9888;'
    if ($StatusCode -eq 404) { $icon = '&#128269;' }
    if ($StatusCode -eq 403) { $icon = '&#128274;' }

    return @"
<section class="container section">
  <div class="error-panel">
    <span class="error-code" aria-hidden="true">$StatusCode</span>
    <span class="error-icon" aria-hidden="true">$icon</span>
    <h1 class="error-heading">$(HtmlEncode $Heading)</h1>
    <p class="error-text">$(HtmlEncode $Message)</p>
    <div class="error-actions">
      <a class="btn btn-primary" href="/">Back to home page</a>
      <a class="btn btn-outline" href="/complaints">Go to reports</a>
    </div>
  </div>
</section>
"@
}
