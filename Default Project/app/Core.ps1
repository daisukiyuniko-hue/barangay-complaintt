# ============================================================================
#  Core.ps1 - Configuration, helpers, HTTP request/response plumbing
#  Barangay Complaint & Concern Reporting System
# ============================================================================

# ----------------------------------------------------------------- settings --
$global:Config = @{
    # --- identity of the "business" -------------------------------------
    SiteName        = 'Barangay Complaint & Concern Reporting System'
    BarangayName    = 'Barangay San Isidro'
    Municipality    = 'City of Antipolo'
    Tagline         = 'Your voice, our action. Report a concern in under a minute.'
    ShortDescription = 'The official online complaint and concern reporting system of Barangay San Isidro. Report potholes, broken streetlights, water interruptions, waste buildup, noise disturbances and other community concerns online, then track every report from Pending to Resolved without visiting the Barangay Hall.'

    # --- server ----------------------------------------------------------
    Port            = 8080
    Host            = 'localhost'

    # --- security --------------------------------------------------------
    SessionHours    = 8
    Pbkdf2Iterations = 120000     # PBKDF2-HMAC-SHA1 work factor
    CookieName      = 'bcr_session'

    # --- pagination ------------------------------------------------------
    PageSize        = 8

    # --- support ---------------------------------------------------------
    OfficeHours     = 'Monday - Friday, 8:00 AM - 5:00 PM'
    Hotline         = '+63 900 000 0000'
    Email           = 'barangay.sanisidro@example.gov.ph'
    Address         = 'Barangay Hall, Purok 3, San Isidro, Antipolo City'
}

# Reference data shared by controllers + views
$global:Categories = @(
    @{ Value = 'Road & Infrastructure'; Hint = 'Potholes, unfinished roads, broken sidewalks, missing street signs' }
    @{ Value = 'Water & Sanitation';    Hint = 'Water interruptions, leaking pipes, solid waste, septic tank issues' }
    @{ Value = 'Electricity & Utilities'; Hint = 'Power outages, downed electric lines, non-working streetlights' }
    @{ Value = 'Health & Safety';       Hint = 'Accident hazards, flooding, fire risk, public health concerns' }
    @{ Value = 'Noise & Nuisance';      Hint = 'Loud noise, barking dogs, foul odours, neighbour disputes' }
    @{ Value = 'Peace & Order';         Hint = 'Vandalism, theft, loitering, suspicious activity' }
    @{ Value = 'Education & Youth';     Hint = 'School concerns, sports facilities, youth programs' }
    @{ Value = 'Other Concern';         Hint = 'Anything else that affects your barangay' }
)

$global:Priorities = @(
    @{ Value = 'Low';    Hint = 'Can wait for the next maintenance cycle' }
    @{ Value = 'Medium'; Hint = 'Affects daily life and should be scheduled soon' }
    @{ Value = 'High';   Hint = 'Needs attention within a few days' }
    @{ Value = 'Urgent'; Hint = 'Dangerous or blocking basic services right now' }
)

$global:Statuses = @(
    @{ Value = 'Pending';   Hint = 'Report received and awaiting initial review' }
    @{ Value = 'In Review'; Hint = 'A committee member is validating and acting on it' }
    @{ Value = 'Resolved';  Hint = 'Action completed and confirmed' }
    @{ Value = 'Rejected';  Hint = 'Outside the barangay''s scope or duplicate of another report' }
)

# Confirmation messages shown after a redirect. The controller adds ?ok=<key>
# plus any values it wants interpolated, so a success message survives the
# round trip without needing server-side state.
$global:FlashMessages = @{
    welcome        = @{ type = 'success'; message = 'Welcome, {name}. Your account is ready.' }
    created        = @{ type = 'success'; message = 'Report {ref} was submitted successfully. The barangay has been notified.' }
    updated        = @{ type = 'success'; message = 'Report {ref} has been updated.' }
    deleted        = @{ type = 'success'; message = 'Report {ref} has been permanently deleted.' }
    statuschanged  = @{ type = 'success'; message = '{ref} is now marked as {status}.' }
    profileupdated = @{ type = 'success'; message = 'Your profile has been updated.' }
    pwchanged      = @{ type = 'success'; message = 'Your password has been changed. Other devices have been signed out.' }
    usercreated    = @{ type = 'success'; message = 'Account created for {name} ({email}).' }
    userdeleted    = @{ type = 'success'; message = 'Account for {name} deleted, together with {count} report(s).' }
    userrole       = @{ type = 'success'; message = '{name} is now {role}.' }
    useractive     = @{ type = 'success'; message = '{name} has been reactivated.' }
    userinactive   = @{ type = 'success'; message = '{name} has been deactivated.' }
    pwreset        = @{ type = 'success'; message = 'New password set for {name}. They must sign in again.' }
    loggedout      = @{ type = 'success'; message = 'You have been signed out. Thank you.' }
    selfchange     = @{ type = 'warning'; message = 'You cannot change your own access level or status.' }
    lastadmin      = @{ type = 'error';   message = 'You cannot remove or demote the last active administrator account.' }
    weakpassword   = @{ type = 'error';   message = 'That password does not meet the security rules. Minimum 8 characters with a letter, a number and a special character.' }
}

function Get-FlashUrl {
    <#
        Builds a redirect target that will display a confirmation message.
        Usage:  Send-Redirect ... -Location (Get-FlashUrl '/dashboard' 'welcome' @{ name = $user.name })
    #>
    param([string]$Path, [string]$Key, [hashtable]$Values = @{})

    $url = $Path
    $params = @('ok=' + [System.Net.WebUtility]::UrlEncode($Key))
    if ($null -ne $Values) {
        foreach ($k in $Values.Keys) {
            $v = [string]$Values[$k]
            if (-not [string]::IsNullOrWhiteSpace($v)) {
                $params += ([System.Net.WebUtility]::UrlEncode($k) + '=' + [System.Net.WebUtility]::UrlEncode($v))
            }
        }
    }
    $separator = if ($url.Contains('?')) { '&' } else { '?' }
    return $url + $separator + ($params -join '&')
}

# ------------------------------------------------------------------ helpers --
function HtmlEncode {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function New-RandomBytes {
    param([int]$Count = 32)
    $bytes = New-Object byte[] $Count
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return $bytes
}

function ConvertTo-Base64Url {
    param([byte[]]$Bytes)
    return ([System.Convert]::ToBase64String($Bytes)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-Base64Url {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return (New-Object byte[] 0) }
    $padded = $Text.Replace('-', '+').Replace('_', '/')
    switch ($padded.Length % 4) {
        2 { $padded += '==' }
        3 { $padded += '=' }
        1 { throw 'Invalid base64url value' }
    }
    return [System.Convert]::FromBase64String($padded)
}

function New-Id {
    param([string]$Prefix = 'id')
    return ('{0}_{1}' -f $Prefix, (ConvertTo-Base64Url (New-RandomBytes -Count 9)))
}

function Get-NowIso { return [DateTime]::UtcNow.ToString('o') }

function Get-DateTimeFromIso {
    param([string]$Iso)
    $dt = [DateTime]::MinValue
    if ([DateTime]::TryParse($Iso, [ref]$dt)) { return $dt.ToLocalTime() }
    return [DateTime]::MinValue
}

# Tiny {{TOKEN}} template filler - avoids -f operator so literal braces are safe.
function Expand-Template {
    param([string]$Template, [hashtable]$Values)
    if ($null -eq $Values) { return $Template }
    foreach ($key in @($Values.Keys)) {
        $Template = $Template.Replace('{{' + $key + '}}', [string]$Values[$key])
    }
    return $Template
}

function Join-NonEmpty {
    param([string[]]$Parts, [string]$Separator = ' ')
    return (($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join $Separator)
}

# ------------------------------------------------------------ request input --
function ConvertFrom-FormBody {
    param([string]$Raw)
    $result = @{}
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $result }
    foreach ($pair in ($Raw -split '&')) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $idx = $pair.IndexOf('=')
        if ($idx -lt 0) { $key = $pair; $value = '' }
        else { $key = $pair.Substring(0, $idx); $value = $pair.Substring($idx + 1) }
        $key = [System.Net.WebUtility]::UrlDecode($key.Replace('+', ' '))
        $value = [System.Net.WebUtility]::UrlDecode($value.Replace('+', ' '))
        if ($result.ContainsKey($key)) {
            $result[$key] = @($result[$key]) + $value
        } else {
            $result[$key] = $value
        }
    }
    return $result
}

function Get-FormValue {
    param([hashtable]$Body, [string]$Name, [string]$Default = '')
    if ($null -ne $Body -and $Body.ContainsKey($Name)) {
        $v = $Body[$Name]
        if ($v -is [array]) { $v = $v[-1] }
        if ($null -eq $v) { return $Default }
        return ([string]$v).Trim()
    }
    return $Default
}

function Get-QueryValue {
    param($Request, [string]$Name, [string]$Default = '')
    try {
        $v = $Request.QueryString[$Name]
        if ($null -ne $v -and -not [string]::IsNullOrWhiteSpace([string]$v)) { return ([string]$v).Trim() }
    } catch { }
    return $Default
}

# --------------------------------------------------------- response writers --
function Send-Body {
    param($Response, [int]$StatusCode, [byte[]]$Bytes, [string]$ContentType, [switch]$SkipBody)
    try {
        $Response.StatusCode = $StatusCode
        $Response.ContentType = $ContentType
        $Response.ContentLength64 = $Bytes.Length
        $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
        $Response.OutputStream.Flush()
    } catch { }
}

function Send-Html {
    param($Response, [string]$Html, [int]$StatusCode = 200)
    Send-Body -Response $Response -StatusCode $StatusCode `
              -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Html)) `
              -ContentType 'text/html; charset=utf-8'
}

function Send-Text {
    param($Response, [string]$Text, [int]$StatusCode = 200, [string]$ContentType = 'text/plain; charset=utf-8')
    Send-Body -Response $Response -StatusCode $StatusCode `
              -Bytes ([System.Text.Encoding]::UTF8.GetBytes($Text)) -ContentType $ContentType
}

function Send-Redirect {
    param($Response, [string]$Location, [int]$StatusCode = 302)
    try {
        $Response.StatusCode = $StatusCode
        $Response.Headers['Location'] = $Location
        $Response.ContentType = 'text/plain; charset=utf-8'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Redirecting to $Location")
        $Response.ContentLength64 = $bytes.Length
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $Response.OutputStream.Flush()
    } catch { }
}

function Send-Json {
    param($Response, $Data, [int]$StatusCode = 200)
    $json = $Data | ConvertTo-Json -Depth 10
    Send-Text -Response $Response -Text $json -StatusCode $StatusCode -ContentType 'application/json; charset=utf-8'
}

function Send-StaticAsset {
    param($Response, [string]$RootPath, [string]$RelativePath)

    $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\') + '\'
    $target   = [System.IO.Path]::GetFullPath((Join-Path $RootPath $RelativePath))
    # Block path traversal (../../etc/passwd)
    if (-not $target.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        Send-ErrorPage -Response $Response -StatusCode 404 -Heading 'Page not found' `
            -Message 'The file you requested does not exist.'
        return
    }
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        Send-ErrorPage -Response $Response -StatusCode 404 -Heading 'Page not found' `
            -Message 'The file you requested does not exist.'
        return
    }

    $ext  = ([System.IO.Path]::GetExtension($target)).ToLowerInvariant()
    $mime = switch ($ext) {
        '.css'  { 'text/css; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        '.svg'  { 'image/svg+xml' }
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.webp' { 'image/webp' }
        '.ico'  { 'image/x-icon' }
        '.json' { 'application/json; charset=utf-8' }
        '.woff2'{ 'font/woff2' }
        '.txt'  { 'text/plain; charset=utf-8' }
        default { 'application/octet-stream' }
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($target)
        # Revalidate every time so edits to the CSS/JS/SVG show up on refresh.
        $Response.Headers['Cache-Control'] = 'no-cache, must-revalidate'
        Send-Body -Response $Response -StatusCode 200 -Bytes $bytes -ContentType $mime
    } catch {
        Send-ErrorPage -Response $Response -StatusCode 500 -Heading 'Something went wrong' `
            -Message 'The asset could not be loaded.'
    }
}

# ------------------------------------------------------------- error pages ---
function Send-ErrorPage {
    param($Response, [int]$StatusCode, [string]$Heading, [string]$Message, [object]$User = $null)

    $titles = @{ 403 = 'Access denied'; 404 = 'Page not found'; 405 = 'Method not allowed'; 500 = 'Server error' }
    if (-not $titles.ContainsKey($StatusCode)) { $titles[$StatusCode] = 'Error' }

    $bodyHtml = ''
    try   { $bodyHtml = New-ErrorBody -StatusCode $StatusCode -Heading $Heading -Message $Message }
    catch { $bodyHtml = '<section class="container section"><h1>' + (HtmlEncode $Heading) +
                        '</h1><p>' + (HtmlEncode $Message) + '</p></section>' }

    $html = ''
    try {
        $html = New-HtmlDocument `
            -Title ("$($StatusCode) - " + $titles[$StatusCode]) `
            -ActiveNav '' -User $User -BodyHtml $bodyHtml
    }
    catch {
        # Never let a rendering failure inside the error page produce a blank
        # response - fall back to a minimal self-contained document.
        $html = '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">' +
                '<meta name="viewport" content="width=device-width, initial-scale=1">' +
                '<title>' + (HtmlEncode $Heading) + '</title>' +
                '<style>body{font-family:Segoe UI,Arial,sans-serif;background:#f9fafb;color:#344054;' +
                'margin:0;padding:48px 20px}main{max-width:640px;margin:0 auto;background:#fff;' +
                'border:1px solid #e4e7ec;border-radius:12px;padding:32px}h1{margin:0 0 8px;' +
                'font-size:1.5rem;color:#101828}p{margin:0;color:#475467}</style></head><body>' +
                '<main><h1>' + (HtmlEncode $Heading) + '</h1><p>' + (HtmlEncode $Message) + '</p></main>' +
                '</body></html>'
    }

    Send-Html -Response $Response -Html $html -StatusCode $StatusCode
}

# ----------------------------------------------------------------- dispatch --
function Invoke-Request {
    param($Context)

    $request  = $Context.Request
    $response = $Context.Response

    $method = $request.HttpMethod.ToUpperInvariant()
    $path   = [System.Net.WebUtility]::UrlDecode($request.Url.AbsolutePath)

    # Normalise trailing slashes: /complaints/ -> /complaints
    if ($path.Length -gt 1) { $path = $path.TrimEnd('/') }
    if ([string]::IsNullOrWhiteSpace($path)) { $path = '/' }

    # ---- request body (only for methods that carry one) -------------------
    $body = @{}
    if ($method -in @('POST', 'PUT', 'PATCH')) {
        try {
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $raw = $reader.ReadToEnd()
            $reader.Close()
            $body = ConvertFrom-FormBody $raw
        } catch { $body = @{} }
    }

    # ---- shared request context -------------------------------------------
    $ctx = @{
        Request   = $request
        Response  = $response
        Method    = $method
        Path      = $path
        Body      = $body
        Query     = $request.QueryString
        Auth      = (Get-AuthContext -Request $request)
        Flash     = $null
        FormData  = @{}
        Errors    = @{}
        Title     = ''
    }

    try {
        $handled = $false

        # -------- public / static -------------------------------------------
        if ($path -eq '/' -and $method -in @('GET', 'HEAD')) {
            Invoke-PublicHome -Ctx $ctx; $handled = $true
        }
        elseif ($path -like '/img/*' -or $path -like '/css/*' -or $path -like '/js/*') {
            if ($method -in @('GET', 'HEAD')) {
                Invoke-StaticAsset -Ctx $ctx; $handled = $true
            }
        }
        elseif ($path -eq '/favicon.ico' -and $method -in @('GET', 'HEAD')) {
            Invoke-StaticAsset -Ctx $ctx -RelativePath 'img/favicon.svg'; $handled = $true
        }
        elseif ($path -eq '/health' -and $method -eq 'GET') {
            Invoke-HealthCheck -Ctx $ctx; $handled = $true
        }

        # -------- authentication ---------------------------------------------
        if (-not $handled -and $path -eq '/login') {
            if ($method -eq 'GET')   { Invoke-ShowLogin  -Ctx $ctx; $handled = $true }
            elseif ($method -eq 'POST') { Invoke-DoLogin    -Ctx $ctx; $handled = $true }
        }
        if (-not $handled -and $path -eq '/register') {
            if ($method -eq 'GET')   { Invoke-ShowRegister -Ctx $ctx; $handled = $true }
            elseif ($method -eq 'POST') { Invoke-DoRegister   -Ctx $ctx; $handled = $true }
        }
        if (-not $handled -and $path -eq '/logout') {
            if ($method -in @('POST', 'GET')) { Invoke-DoLogout -Ctx $ctx; $handled = $true }
        }

        # -------- dashboards & profile (protected) ---------------------------
        if (-not $handled -and $path -eq '/dashboard') {
            if ($method -ne 'GET') { $handled = $false } else {
                if (Protect-Page -Ctx $ctx) { Invoke-Dashboard -Ctx $ctx }
                $handled = $true
            }
        }
        if (-not $handled -and $path -eq '/profile') {
            if ($method -eq 'GET') {
                if (Protect-Page -Ctx $ctx) { Invoke-Profile -Ctx $ctx }
                $handled = $true
            }
            elseif ($method -eq 'POST') {
                if (Protect-Page -Ctx $ctx) { Invoke-UpdateProfile -Ctx $ctx }
                $handled = $true
            }
        }
        if (-not $handled -and $path -eq '/profile/password') {
            if ($method -eq 'GET') {
                if (Protect-Page -Ctx $ctx) { Invoke-ChangePasswordForm -Ctx $ctx }
                $handled = $true
            }
            elseif ($method -eq 'POST') {
                if (Protect-Page -Ctx $ctx) { Invoke-ChangePassword -Ctx $ctx }
                $handled = $true
            }
        }

        # -------- complaints CRUD --------------------------------------------
        if (-not $handled -and $path -eq '/complaints') {
            if ($method -eq 'GET') {
                if (Protect-Page -Ctx $ctx) { Invoke-ComplaintList -Ctx $ctx }
                $handled = $true
            }
        }
        if (-not $handled -and $path -eq '/complaints/new') {
            if ($method -eq 'GET') {
                if (Protect-Page -Ctx $ctx) { Invoke-ComplaintForm -Ctx $ctx }
                $handled = $true
            }
            elseif ($method -eq 'POST') {
                if (Protect-Page -Ctx $ctx) { Invoke-ComplaintCreate -Ctx $ctx }
                $handled = $true
            }
        }
        if (-not $handled -and $path -match '^/complaints/([^/]+)$') {
            $id = $Matches[1]
            if ($method -eq 'GET') {
                if (Protect-Page -Ctx $ctx) { Invoke-ComplaintDetail -Ctx $ctx -Id $id }
                $handled = $true
            }
        }
        if (-not $handled -and $path -match '^/complaints/([^/]+)/edit$') {
            $id = $Matches[1]
            if ($method -eq 'GET') {
                if (Protect-Page -Ctx $ctx) { Invoke-ComplaintForm -Ctx $ctx -Id $id }
                $handled = $true
            }
            elseif ($method -eq 'POST') {
                if (Protect-Page -Ctx $ctx) { Invoke-ComplaintUpdate -Ctx $ctx -Id $id }
                $handled = $true
            }
        }
        if (-not $handled -and $path -match '^/complaints/([^/]+)/delete$') {
            $id = $Matches[1]
            if ($method -eq 'GET') {
                if (Protect-Page -Ctx $ctx) { Invoke-ComplaintDeleteConfirm -Ctx $ctx -Id $id }
                $handled = $true
            }
            elseif ($method -eq 'POST') {
                if (Protect-Page -Ctx $ctx) { Invoke-ComplaintDelete -Ctx $ctx -Id $id }
                $handled = $true
            }
        }
        if (-not $handled -and $path -match '^/complaints/([^/]+)/status$') {
            $id = $Matches[1]
            if ($method -eq 'POST') {
                if (Protect-Page -Ctx $ctx) { Invoke-ComplaintStatusUpdate -Ctx $ctx -Id $id }
                $handled = $true
            }
        }

        # -------- admin: user management ------------------------------------
        if (-not $handled -and $path -eq '/users') {
            if ($method -eq 'GET') {
                if (Protect-AdminPage -Ctx $ctx) { Invoke-UserList -Ctx $ctx }
                $handled = $true
            }
        }
        if (-not $handled -and $path -eq '/users/new') {
            if ($method -eq 'GET') {
                if (Protect-AdminPage -Ctx $ctx) { Invoke-UserCreateForm -Ctx $ctx }
                $handled = $true
            }
            elseif ($method -eq 'POST') {
                if (Protect-AdminPage -Ctx $ctx) { Invoke-UserCreate -Ctx $ctx }
                $handled = $true
            }
        }
        if (-not $handled -and $path -match '^/users/([^/]+)/delete$') {
            $id = $Matches[1]
            if ($method -eq 'GET') {
                if (Protect-AdminPage -Ctx $ctx) { Invoke-UserDeleteConfirm -Ctx $ctx -Id $id }
                $handled = $true
            }
            elseif ($method -eq 'POST') {
                if (Protect-AdminPage -Ctx $ctx) { Invoke-UserAction -Ctx $ctx -Id $id -Verb 'delete' }
                $handled = $true
            }
        }
        if (-not $handled -and $path -match '^/users/([^/]+)/(toggle|role|reset-password)$') {
            $id   = $Matches[1]
            $verb = $Matches[2]
            if ($method -eq 'POST') {
                if (Protect-AdminPage -Ctx $ctx) { Invoke-UserAction -Ctx $ctx -Id $id -Verb $verb }
                $handled = $true
            }
        }

        # -------- fallback ----------------------------------------------------
        if (-not $handled) {
            $ctx.Response.Headers['Allow'] = 'GET, POST'
            Send-ErrorPage -Response $ctx.Response -StatusCode 404 `
                -Heading 'We could not find that page' `
                -Message 'The link may be old or mistyped. Try starting from the home page.' `
                -User $ctx.Auth.User
        }
    }
    catch {
        $message = $_.Exception.Message
        $where   = ''
        try   { $where = ($_.InvocationInfo.PositionMessage -split "`n")[0] } catch { }
        Write-Host ('  ! 500 ' + $ctx.Path + ' :: ' + $message) -ForegroundColor Red
        if ($where) { Write-Host ('         at ' + $where.Trim()) -ForegroundColor DarkYellow }
        try {
            Send-ErrorPage -Response $response -StatusCode 500 `
                -Heading 'Something went wrong on our side' `
                -Message 'The page could not be displayed. Please try again, and report the problem if it keeps happening.' `
                -User $ctx.Auth.User
        }
        catch {
            # Absolute last resort so the browser never gets an empty response.
            Write-Host ('  ! 500 (fallback) ' + $message) -ForegroundColor Red
            Send-Text -Response $response -Text "Error 500 - Something went wrong on our side. Please go back and try again." -StatusCode 500
        }
    }
    finally {
        try { $response.Close() } catch { }
    }
}

# ------------------------------------------------------------------ startup --
function Test-PortInUse {
    param([int]$Port)
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect('127.0.0.1', $Port)
        $client.Close()
        return $true
    } catch { return $false }
}

function Test-AppAlreadyRunning {
    <# Answers "is the thing on this port already our app?" #>
    param([int]$Port)
    try {
        $req  = [System.Net.HttpWebRequest]::Create(("http://localhost:{0}/health" -f $Port))
        $req.Timeout = 2500
        $req.AllowAutoRedirect = $false
        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $body = $reader.ReadToEnd()
        $reader.Close(); $resp.Close()
        return ($body -match 'Complaint')
    } catch { return $false }
}

function Open-LandingPage {
    try {
        Start-Job -Name 'open-landing-page' -ScriptBlock {
            param($url)
            Start-Sleep -Milliseconds 900
            Start-Process $url
        } -ArgumentList (Get-BaseUrl) | Out-Null
    } catch { }
}

function Initialize-App {
    param([int]$Port = 0, [switch]$Reset, [switch]$NoBrowser)

    if ($Port -gt 0) { $global:Config.Port = $Port }

    $global:PublicDir = Join-Path $global:AppRoot 'public'

    # ---- is the port already taken? ---------------------------------------
    if (Test-PortInUse $global:Config.Port) {
        if (Test-AppAlreadyRunning $global:Config.Port) {
            Write-Host ''
            Write-Host '  The server is ALREADY running.' -ForegroundColor Yellow
            Write-Host ('  Opening ' + (Get-BaseUrl)) -ForegroundColor White
            if (-not $NoBrowser) { Open-LandingPage }
            Write-Host ''
            Write-Host '  Nothing new was started. Close any old server window to stop it.' -ForegroundColor DarkGray
            Write-Host ''
            exit 0
        }

        Write-Host ''
        Write-Host ('  ERROR: Port {0} is already in use by another program.' -f $global:Config.Port) -ForegroundColor Red
        Write-Host ''
        Write-Host '  That is not this application, so it cannot be shown.' -ForegroundColor White
        Write-Host '  Close the other program, or start on a different port:' -ForegroundColor White
        Write-Host '      .\start.bat -Port 8090' -ForegroundColor Cyan
        Write-Host ''
        try { Read-Host 'Press Enter to close this window' | Out-Null } catch { }
        exit 1
    }

    # Fail fast rather than letting HttpListener throw a raw .NET error.
    try {
        $probe = New-Object System.Net.HttpListener
        $probe.Prefixes.Add((Get-BaseUrl))
        $probe.Start(); $probe.Stop(); $probe.Close()
    } catch {
        Write-Host ''
        Write-Host '  ERROR: The web server could not start.' -ForegroundColor Red
        Write-Host ('  Reason: ' + $_.Exception.Message) -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  Try a different port, for example:' -ForegroundColor White
        Write-Host '      .\start.bat -Port 8090' -ForegroundColor Cyan
        Write-Host ''
        try { Read-Host 'Press Enter to close this window' | Out-Null } catch { }
        exit 1
    }

    Initialize-Database -Reset:$Reset
}

function Get-BaseUrl {
    return ('http://{0}:{1}/' -f $global:Config.Host, $global:Config.Port)
}

function Start-WebServer {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add((Get-BaseUrl))
    $listener.Start()

    Write-Host ''
    Write-Host '  =============================================================' -ForegroundColor DarkCyan
    Write-Host '   BARANGAY COMPLAINT & CONCERN REPORTING SYSTEM' -ForegroundColor Cyan
    Write-Host '  =============================================================' -ForegroundColor DarkCyan
    Write-Host ('   Running at   : ' + (Get-BaseUrl)) -ForegroundColor White
    Write-Host ('   Database file: ' + $global:DbPath) -ForegroundColor DarkGray
    Write-Host ''
    Write-Host ('   Open in browser : ' + (Get-BaseUrl)) -ForegroundColor White
    Write-Host ''
    Write-Host '   ADMIN LOGIN    admin@barangay.gov.ph     Admin@12345' -ForegroundColor Yellow
    Write-Host '   RESIDENT LOGIN resident@barangay.gov.ph  Resident@12345' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '   IMPORTANT: keep this window open while you use the system.' -ForegroundColor White
    Write-Host '   If you close it, the address above will stop working.' -ForegroundColor DarkGray
    Write-Host '   To stop the server press Ctrl+C in this window.' -ForegroundColor DarkGray
    Write-Host '  =============================================================' -ForegroundColor DarkCyan
    Write-Host ''

    try {
        while ($listener.IsListening) {
            $context = $null
            try { $context = $listener.GetContext() }
            catch { break }
            if ($null -eq $context) { continue }

            $line = '{0,-6} {1}' -f $context.Request.HttpMethod, $context.Request.RawUrl
            Write-Host ('  ' + $line) -ForegroundColor DarkGray
            Invoke-Request -Context $context
        }
    }
    finally {
        try { $listener.Stop(); $listener.Close() } catch { }
        Write-Host ''
        Write-Host '  Server stopped. Data is safely stored in data\db.json' -ForegroundColor DarkCyan
    }
}
