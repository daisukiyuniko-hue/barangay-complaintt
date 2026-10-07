# ============================================================================
#  Controllers/PublicController.ps1 - Landing page and the signed-in dashboard
# ============================================================================

# ------------------------------------------------------------ LANDING PAGE --
function Invoke-PublicHome {
    param($Ctx)

    $user = $Ctx.Auth.User
    $barangay = HtmlEncode $global:Config.BarangayName
    $municipality = HtmlEncode $global:Config.Municipality
    $description = HtmlEncode $global:Config.ShortDescription
    $tagline = HtmlEncode $global:Config.Tagline

    # --- service cards (this is the "menu" of what the business offers) ----
    $icons = @{
        'Road & Infrastructure'   = '/img/cat-road.svg'
        'Water & Sanitation'      = '/img/cat-water.svg'
        'Electricity & Utilities' = '/img/cat-power.svg'
        'Health & Safety'         = '/img/cat-health.svg'
        'Noise & Nuisance'        = '/img/cat-noise.svg'
        'Peace & Order'           = '/img/cat-peace.svg'
        'Education & Youth'       = '/img/cat-education.svg'
        'Other Concern'           = '/img/cat-other.svg'
    }
    $serviceCards = ''
    $i = 0
    foreach ($c in $global:Categories) {
        $i++
        $alt = 'Icon for ' + $c.Value
        $serviceCards += @"
<article class="service-card">
  <div class="service-icon">
    <img src="$($icons[$c.Value])" width="56" height="56" alt="$alt" loading="lazy">
  </div>
  <h3 class="service-title">$(HtmlEncode $c.Value)</h3>
  <p class="service-text">$(HtmlEncode $c.Hint)</p>
  <p class="service-step"><span class="service-num">$i</span></p>
</article>
"@
    }

    # --- how it works ------------------------------------------------------
    $steps = @(
        @{ n = '1'; t = 'Create your free account'; d = 'Register with your name, email and a password. It takes about a minute and you only do it once.' }
        @{ n = '2'; t = 'Describe your concern'; d = 'Pick a category, tell us how urgent it is, where it is, and describe the problem in your own words.' }
        @{ n = '3'; t = 'Get a reference number'; d = 'Your report is filed immediately with a reference like BCR-2026-0001 so the office can track it.' }
        @{ n = '4'; t = 'Follow it until resolved'; d = 'Sign in any time to see the status and read notes from the barangay committee.' }
    )
    $stepHtml = ''
    foreach ($s in $steps) {
        $stepHtml += @"
<li class="step-card">
  <span class="step-num">$(HtmlEncode $s.n)</span>
  <h3 class="step-title">$(HtmlEncode $s.t)</h3>
  <p class="step-text">$(HtmlEncode $s.d)</p>
</li>
"@
    }

    # --- commitments -------------------------------------------------------
    $commitments = @(
        @{ v = 'Free';    l = 'No fee to report';  i = '/img/cat-other.svg' }
        @{ v = '24h';     l = 'Target acknowledgement'; i = '/img/cat-other.svg' }
        @{ v = '8';       l = 'Puroks covered';    i = '/img/cat-other.svg' }
        @{ v = '0';       l = 'Forms to walk in with'; i = '/img/cat-other.svg' }
    )
    $commitHtml = ''
    foreach ($c in $commitments) {
        $commitHtml += '<div class="commit-tile"><p class="commit-value">' + (HtmlEncode $c.v) +
                       '</p><p class="commit-label">' + (HtmlEncode $c.l) + '</p></div>'
    }

    # --- FAQ ---------------------------------------------------------------
    $faqs = @(
        @{ q = 'Do I need an account to report a problem?'
           a = 'Yes. Reporting requires a free resident account so the barangay can send you updates and so that your contact details are protected. Creating an account takes about a minute.' }
        @{ q = 'Can anybody see my report?'
           a = 'Only you and authorized barangay administrators. Residents can see their own reports only; they cannot browse reports filed by their neighbours.' }
        @{ q = 'What happens after I submit a report?'
           a = 'You immediately receive a reference number. The status moves from Pending to In Review and finally to Resolved, and you can read notes from the committee at any time.' }
        @{ q = 'Can I change or withdraw my report?'
           a = 'Yes. While your report is still Pending you can edit the details or delete it completely. Once the committee starts reviewing it, the record is locked so the history stays accurate.' }
        @{ q = 'Is my password stored safely?'
           a = 'Yes. Passwords are hashed with PBKDF2 using a random salt per account. The plain text password is never written to the database or to any log file.' }
        @{ q = 'What if the problem is an emergency?'
           a = 'Call the Barangay Hall hotline at ' + $global:Config.Hotline + ' or contact the Philippine National Police or Fire Department immediately. This system is for non-emergency concerns.' }
    )
    $faqHtml = ''
    foreach ($f in $faqs) {
        $faqHtml += @"
<details class="faq-item">
  <summary class="faq-question"><span>$(HtmlEncode $f.q)</span><span class="faq-plus" aria-hidden="true"></span></summary>
  <div class="faq-answer"><p>$(HtmlEncode $f.a)</p></div>
</details>
"@
    }

    # --- primary call to action depends on sign-in state --------------------
    if ($null -eq $user) {
        $ctaButtons = @'
<a class="btn btn-primary btn-lg" href="/register">Create a free account</a>
<a class="btn btn-outline btn-lg" href="/login">I already have an account</a>
'@
        $heroNote = '<p class="hero-note">Free to use &middot; Takes about a minute &middot; Available 24/7</p>'
        $signedInBanner = ''
    }
    else {
        $firstName = HtmlEncode (@(([string]$user.name) -split ' ') | Where-Object { $_ -ne '' } | Select-Object -First 1)
        $ctaButtons = '<a class="btn btn-primary btn-lg" href="/complaints/new">Report a concern</a>' +
                      '<a class="btn btn-outline btn-lg" href="/complaints">View my reports</a>'
        $heroNote = '<p class="hero-note">Signed in as <strong>' + (HtmlEncode $user.name) + '</strong></p>'
        $signedInBanner = @"
<div class="container">
  <div class="welcome-strip">
    <span class="welcome-icon" aria-hidden="true">&#128075;</span>
    <p>Welcome back, $firstName. Would you like to report a new concern today?</p>
    <a class="btn btn-primary btn-sm" href="/complaints/new">+ New report</a>
  </div>
</div>
"@
    }

    $hotline    = HtmlEncode $global:Config.Hotline
    $officeHours= HtmlEncode $global:Config.OfficeHours
    $address    = HtmlEncode $global:Config.Address
    $contactEmail = HtmlEncode $global:Config.Email

    $body = @"
$signedInBanner

$(New-FlashHtml $Ctx)

<section class="hero">
  <div class="container hero-grid">
    <div class="hero-copy">
      <p class="hero-eyebrow">$barangay &middot; $municipality</p>
      <h1 class="hero-title">Report a barangay concern in under a minute</h1>
      <p class="hero-text">$description</p>
      <div class="hero-actions">$ctaButtons</div>
      $heroNote
    </div>
    <div class="hero-art">
      <img src="/img/hero-barangay.svg" width="560" height="420"
           alt="Illustration of the Barangay Hall with residents reporting a concern about the road and a streetlight">
    </div>
  </div>
</section>

<section class="commit-strip">
  <div class="container commit-grid">$commitHtml</div>
</section>

<section class="section" id="services">
  <div class="container">
    $(New-SectionHeading -Eyebrow 'What you can report' `
        -Heading 'Eight kinds of community concerns we handle' `
        -Sub 'Choose the category that fits your situation. Each one goes straight to the committee responsible for that service.')
    <div class="service-grid">$serviceCards</div>
    <div class="section-cta">
      <a class="btn btn-primary btn-lg" href="/register">Start reporting now</a>
      <span class="section-cta-note">No account yet? Creating one is free and instant.</span>
    </div>
  </div>
</section>

<section class="section section-alt" id="how-it-works">
  <div class="container">
    $(New-SectionHeading -Eyebrow 'How it works' `
        -Heading 'Four simple steps from problem to resolution' `
        -Sub 'You do not need to visit the Barangay Hall, queue at the window, or call the office during working hours.')
    <ol class="steps-grid">$stepHtml</ol>
  </div>
</section>

<section class="section">
  <div class="container about-grid">
    <div class="about-art">
      <img src="/img/about-community.svg" width="520" height="400"
           alt="Illustration of residents of the barangay working together on a clean, safe community">
    </div>
    <div class="about-copy">
      $(New-SectionHeading -Eyebrow 'Why report through this system' `
          -Heading 'A clearer way to get your concerns heard' `
          -Sub 'Traditional paper logs get lost, damaged by rain, or filed away without a reply. This system keeps a clear, timestamped record of every single report.')
      <ul class="check-list">
        <li><span class="check-icon" aria-hidden="true">&#10003;</span><div><strong>A permanent record</strong><p>Your report is stored with a reference number and timestamps, so nothing gets lost or forgotten.</p></div></li>
        <li><span class="check-icon" aria-hidden="true">&#10003;</span><div><strong>Transparent progress</strong><p>See the status change from Pending to Resolved, plus notes from the committee, any time you sign in.</p></div></li>
        <li><span class="check-icon" aria-hidden="true">&#10003;</span><div><strong>Works on your phone</strong><p>The whole site is built mobile-first, so you can report a hazard while standing right in front of it.</p></div></li>
        <li><span class="check-icon" aria-hidden="true">&#10003;</span><div><strong>Your details stay private</strong><p>Only you and authorized barangay administrators can open your reports.</p></div></li>
        <li><span class="check-icon" aria-hidden="true">&#10003;</span><div><strong>Available 24/7</strong><p>Report a problem at two in the morning. The office sees it first thing in the morning.</p></div></li>
      </ul>
    </div>
  </div>
</section>

<section class="section section-alt">
  <div class="container contact-grid">
    <div>
      $(New-SectionHeading -Eyebrow 'Prefer to talk to a person?' `
          -Heading 'You can always come to the Barangay Hall' `
          -Sub 'Online reporting is one option, not the only one. Our office hours and contact details are below.')
      <dl class="detail-list detail-list-card">
        <div><dt>Office hours</dt><dd>$officeHours</dd></div>
        <div><dt>Hotline</dt><dd>$hotline</dd></div>
        <div><dt>Email</dt><dd><a href="mailto:$contactEmail">$contactEmail</a></dd></div>
        <div><dt>Address</dt><dd>$address</dd></div>
      </dl>
    </div>
    <div class="contact-card">
      <h3 class="contact-title">Barangay emergency contacts</h3>
      <p class="contact-note">For emergencies, do not wait for an online report.</p>
      <ul class="contact-list">
        <li><span>Barangay Hall</span><strong>$hotline</strong></li>
        <li><span>Philippine National Police</span><strong>911</strong></li>
        <li><span>Fire and Rescue</span><strong>160</strong></li>
        <li><span>National Emergency Hotline</span><strong>911</strong></li>
      </ul>
    </div>
  </div>
</section>

<section class="section" id="faq">
  <div class="container container-narrow">
    $(New-SectionHeading -Eyebrow 'Questions' -Heading 'Frequently asked questions' `
        -Sub 'Everything residents usually ask before filing their first report.')
    <div class="faq-list">$faqHtml</div>
  </div>
</section>

<section class="final-cta">
  <div class="container final-cta-inner">
    <div>
      <h2 class="final-cta-title">$tagline</h2>
      <p class="final-cta-text">Register once and keep track of every concern you report to $barangay.</p>
    </div>
    <div class="final-cta-actions">
      <a class="btn btn-light btn-lg" href="/register">Create a free account</a>
      <a class="btn btn-ghost-light btn-lg" href="/login">Sign in</a>
    </div>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title '' -BodyHtml $body -ActiveNav 'home' -User $user -Wide)
}

# ---------------------------------------------------------------- DASHBOARD --
function Invoke-Dashboard {
    param($Ctx)

    $user    = $Ctx.Auth.User
    $csrf    = Get-CsrfToken -Ctx $Ctx
    $isAdmin = Test-IsAdmin $user
    $firstName = HtmlEncode (@(([string]$user.name) -split ' ') | Where-Object { $_ -ne '' } | Select-Object -First 1)

    $scopeId = if ($isAdmin) { '' } else { [string]$user.id }
    $stats   = Get-ComplaintStats -UserId $scopeId

    $greeting = if ($user.role -eq 'admin') { 'Administrator dashboard' } else { 'Welcome back, ' + $firstName }

    # --- recent reports -----------------------------------------------------
    $visible = @(Get-VisibleComplaints -Ctx $Ctx)
    $recent  = @($visible | Sort-Object -Property createdAt -Descending | Select-Object -First 5)

    $recentHtml = ''
    foreach ($c in $recent) {
        $recentHtml += New-ComplaintRow -Complaint $c -Viewer $user -Compact
    }
    if ($recent.Count -eq 0) {
        if ($isAdmin) {
            $recentHtml = New-EmptyState -Icon '&#128203;' -Title 'No reports have been filed yet' `
                -Message 'As soon as a resident submits a report it will appear here for verification and action.' `
                -Action '<a class="btn btn-primary" href="/complaints/new">File a report</a>'
        } else {
            $recentHtml = New-EmptyState -Icon '&#128221;' -Title 'You have not filed any reports yet' `
                -Message 'Spotted a pothole, a broken streetlight or a pile of garbage? Tell the barangay about it in under a minute.' `
                -Action '<a class="btn btn-primary" href="/complaints/new">Report a concern</a>'
        }
    }

    # --- category breakdown (admin) ---------------------------------------
    $breakdownHtml = ''
    if ($isAdmin -and $visible.Count -gt 0) {
        $groups = @{}
        foreach ($c in $visible) {
            $key = [string]$c.category
            if (-not $groups.ContainsKey($key)) { $groups[$key] = 0 }
            $groups[$key] = $groups[$key] + 1
        }
        $max = 1
        foreach ($k in $groups.Keys) { if ($groups[$k] -gt $max) { $max = $groups[$k] } }
        $sortedKeys = @($groups.Keys | Sort-Object -Property { -$groups[$_] })
        foreach ($k in $sortedKeys) {
            $pct = [Math]::Round(($groups[$k] / $max) * 100)
            $breakdownHtml += @"
<li class="bar-item">
  <span class="bar-label">$(HtmlEncode $k)</span>
  <span class="bar-track"><span class="bar-fill" style="width: $pct%"></span></span>
  <span class="bar-value">$($groups[$k])</span>
</li>
"@
        }
    }

    # --- urgent queue (admin) ----------------------------------------------
    $urgentHtml = ''
    if ($isAdmin) {
        $urgent = @($visible | Where-Object {
            ($_.priority -eq 'Urgent' -or $_.priority -eq 'High') -and $_.status -ne 'Resolved'
        } | Sort-Object -Property createdAt -Descending)

        if ($urgent.Count -gt 0) {
            foreach ($c in @($urgent | Select-Object -First 4)) {
                $prioTone = Get-PriorityTone ([string]$c.priority)
                $statTone = Get-StatusTone ([string]$c.status)
                $href = '/complaints/' + [System.Net.WebUtility]::UrlEncode([string]$c.id)
                $urgentHtml += @"
<li class="urgent-item">
  <a href="$href">
    <span class="badge badge-$prioTone">$(HtmlEncode ([string]$c.priority))</span>
    <span class="urgent-title">$(HtmlEncode ([string]$c.title))</span>
    <span class="badge badge-$statTone">$(HtmlEncode ([string]$c.status))</span>
  </a>
</li>
"@
            }
        }
        else {
            $urgentHtml = '<li class="urgent-empty">No high or urgent reports are waiting. </li>'
        }
    }

    # --- right column ------------------------------------------------------
    $sideHtml = ''
    if ($isAdmin) {
        $allUsers = @(Get-AllUsers)
        $sideHtml += @"
<div class="card">
  <div class="card-head"><h2 class="card-title">Community overview</h2></div>
  <dl class="detail-list">
    <div><dt>Registered accounts</dt><dd>$($allUsers.Count)</dd></div>
    <div><dt>Administrators</dt><dd>$(@($allUsers | Where-Object { $_.role -eq 'admin' }).Count)</dd></div>
    <div><dt>Reports on record</dt><dd>$($stats.Total)</dd></div>
    <div><dt>Resolved</dt><dd>$($stats.Resolved)</dd></div>
    <div><dt>Awaiting action</dt><dd>$($stats.Pending + $stats.InReview)</dd></div>
  </dl>
  <a class="btn btn-outline btn-block" href="/users">Manage resident accounts</a>
</div>

<div class="card">
  <div class="card-head"><h2 class="card-title">Needs attention</h2></div>
  <ul class="urgent-list">$urgentHtml</ul>
</div>
"@
    }
    else {
        $sideHtml += @"
<div class="card card-quiet">
  <div class="card-head"><h2 class="card-title">Your status at a glance</h2></div>
  <dl class="detail-list">
    <div><dt>Reports filed</dt><dd>$($stats.Total)</dd></div>
    <div><dt>Pending</dt><dd>$($stats.Pending)</dd></div>
    <div><dt>In review</dt><dd>$($stats.InReview)</dd></div>
    <div><dt>Resolved</dt><dd>$($stats.Resolved)</dd></div>
  </dl>
  <a class="btn btn-primary btn-block" href="/complaints/new">+ Report a new concern</a>
</div>

<div class="card card-quiet">
  <div class="card-head"><h2 class="card-title">Barangay office</h2></div>
  <p class="card-text">Hotline: $(HtmlEncode $global:Config.Hotline)</p>
  <p class="card-text">$(HtmlEncode $global:Config.OfficeHours)</p>
  <p class="card-text">$(HtmlEncode $global:Config.Address)</p>
</div>
"@
    }

    $sub = if ($isAdmin) {
        'Verify incoming reports, update their status and keep a clear record of every action taken.'
    } else {
        'Here is everything you have reported so far, newest first.'
    }

    $listLink = if ($isAdmin) { '<a class="btn btn-outline" href="/complaints">See all reports</a>' }
                else { '<a class="btn btn-outline" href="/complaints">See all my reports</a>' }

    $breakdownCard = ''
    if ($isAdmin -and $breakdownHtml -ne '') {
        $breakdownCard = @"
<div class="card">
  <div class="card-head"><h2 class="card-title">Reports by category</h2></div>
  <ul class="bar-list">$breakdownHtml</ul>
</div>
"@
    }

    $body = @"
<section class="container section">
  $(New-PageIntro -Eyebrow 'Dashboard' -Heading $greeting -Sub $sub `
        -Actions ('<a class="btn btn-primary" href="/complaints/new">+ New report</a>' + $listLink))

  $(New-FlashHtml $Ctx)

  <div class="stat-grid stat-grid-4">
    $(New-StatTile -Label 'Total reports' -Value $stats.Total -Tone 'brand'   -Hint 'On record')
    $(New-StatTile -Label 'Pending'       -Value $stats.Pending -Tone 'warning' -Hint 'Awaiting first response')
    $(New-StatTile -Label 'In review'     -Value $stats.InReview -Tone 'info' -Hint 'Being worked on now')
    $(New-StatTile -Label 'Resolved'      -Value $stats.Resolved -Tone 'success' -Hint 'Completed and closed')
  </div>

  <div class="dashboard-grid">
    <section class="dash-main">
      <div class="section-head">
        <div>
          <p class="section-eyebrow">Activity</p>
          <h2 class="section-title section-title-sm">$(if ($isAdmin) { 'Latest reports from residents' } else { 'Your latest reports' })</h2>
        </div>
        $listLink
      </div>
      <div class="row-list">$recentHtml</div>
    </section>

    <aside class="side-stack">
      $sideHtml
      $breakdownCard
    </aside>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title 'Dashboard' -BodyHtml $body -ActiveNav 'dashboard' -User $user -CsrfToken $csrf)
}
