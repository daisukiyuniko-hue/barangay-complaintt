# ============================================================================
#  Security.ps1
#   * PBKDF2-HMAC-SHA1 password hashing (salted, 120k iterations)
#   * Server-side sessions with an HttpOnly cookie
#   * CSRF tokens on every state-changing form
#   * Page guards that redirect anonymous visitors to the login page
# ============================================================================

# ---------------------------------------------------------- password hashing --
function New-PasswordRecord {
    <#
        Returns only salt + hash + iteration count. The clear-text password is
        never stored, never logged and never returned to the client.
    #>
    param([Parameter(Mandatory = $true)][string]$Password)

    $salt      = New-RandomBytes -Count 16
    $iterations = [int]$global:Config.Pbkdf2Iterations
    $hash      = Get-Pbkdf2 -Password $Password -Salt $salt -Iterations $iterations

    return [pscustomobject]@{
        passwordSalt      = (ConvertTo-Base64Url $salt)
        passwordHash      = (ConvertTo-Base64Url $hash)
        passwordAlgorithm = 'PBKDF2-HMAC-SHA1'
        passwordIterations = $iterations
    }
}

function Get-Pbkdf2 {
    param([string]$Password, [byte[]]$Salt, [int]$Iterations, [int]$Length = 32)
    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes `
        -ArgumentList ([System.Text.Encoding]::UTF8.GetBytes($Password)), $Salt, $Iterations
    try {
        return $derive.GetBytes($Length)
    } finally {
        $derive.Dispose()
    }
}

function Test-PasswordAgainstRecord {
    param([string]$Password, $User)

    if ($null -eq $User) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$User.passwordHash)) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$User.passwordSalt)) { return $false }

    $iterations = 120000
    if ($User.PSObject.Properties.Name -contains 'passwordIterations' -and $User.passwordIterations) {
        $iterations = [int]$User.passwordIterations
    }

    $expected = ConvertFrom-Base64Url ([string]$User.passwordHash)
    $actual   = Get-Pbkdf2 -Password $Password -Salt (ConvertFrom-Base64Url ([string]$User.passwordSalt)) `
                           -Iterations $iterations -Length $expected.Length

    # Constant-time comparison to avoid leaking information through timing
    if ($expected.Length -ne $actual.Length) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $expected.Length; $i++) {
        $diff = $diff -bor ($expected[$i] -bxor $actual[$i])
    }
    return ($diff -eq 0)
}

function Set-UserPassword {
    param($User, [string]$Password)
    $record = New-PasswordRecord -Password $Password
    $User | Add-Member -NotePropertyName 'passwordSalt'       -NotePropertyValue $record.passwordSalt       -Force
    $User | Add-Member -NotePropertyName 'passwordHash'       -NotePropertyValue $record.passwordHash       -Force
    $User | Add-Member -NotePropertyName 'passwordAlgorithm'  -NotePropertyValue $record.passwordAlgorithm  -Force
    $User | Add-Member -NotePropertyName 'passwordIterations' -NotePropertyValue $record.passwordIterations -Force
    $User | Add-Member -NotePropertyName 'passwordChangedAt'  -NotePropertyValue (Get-NowIso)                 -Force
    $null = Save-User $User
    return $User
}

# ------------------------------------------------------------------- users --
function New-UserRecord {
    param(
        [string]$Name,
        [string]$Email,
        [string]$Password,
        [ValidateSet('admin', 'resident')][string]$Role = 'resident',
        [string]$Phone = '',
        [string]$Address = '',
        [bool]$Active = $true
    )

    $user = [pscustomobject]@{
        id                 = (New-Id 'usr')
        name               = $Name.Trim()
        email              = $Email.Trim().ToLowerInvariant()
        role               = $Role
        phone              = $Phone
        address            = $Address
        active             = $Active
        createdAt          = (Get-NowIso)
        updatedAt          = (Get-NowIso)
        lastLoginAt        = ''
        passwordSalt       = ''
        passwordHash       = ''
        passwordAlgorithm  = ''
        passwordIterations = 0
        passwordChangedAt  = ''
    }
    $user = Set-UserPassword -User $user -Password $Password
    $null = Save-User $user
    return $user
}

function Get-Initials {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '?' }

    # @() is required: a single-word name would otherwise collapse to a plain
    # String, and indexing a String returns a Char which has no Substring().
    $parts = @(($Name -split '\s+') | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) { return '?' }

    $first = [string]$parts[0]
    $last  = if ($parts.Count -gt 1) { [string]$parts[$parts.Count - 1] } else { $first }

    if ([string]::IsNullOrWhiteSpace($first)) { return '?' }
    $a = $first.Substring(0, 1).ToUpperInvariant()
    $b = $last.Substring(0, 1).ToUpperInvariant()
    return ($a + $b).ToUpperInvariant()
}

function Test-IsAdmin {
    param($User)
    return ($null -ne $User -and [string]$User.role -eq 'admin')
}

# ---------------------------------------------------------------- sessions --
function New-Session {
    param([string]$UserId)

    $now   = [DateTime]::UtcNow
    $entry = [pscustomobject]@{
        token      = (ConvertTo-Base64Url (New-RandomBytes -Count 32))
        csrfToken  = (ConvertTo-Base64Url (New-RandomBytes -Count 24))
        userId     = $UserId
        createdAt  = $now.ToString('o')
        expiresAt  = $now.AddHours([int]$global:Config.SessionHours).ToString('o')
        lastSeenAt = $now.ToString('o')
        userAgent  = ''
    }

    $sessions = @(Get-AllSessions)
    $sessions += $entry
    $global:Db.sessions = @($sessions)
    Save-Database
    return $entry
}

function Get-AllSessions { return @($global:Db.sessions) }

function Get-SessionByToken {
    param([string]$Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { return $null }
    return (@(Get-AllSessions) | Where-Object { $_.token -eq $Token } | Select-Object -First 1)
}

function Remove-ExpiredSessions {
    $now = [DateTime]::UtcNow
    $kept = @(@(Get-AllSessions) | Where-Object {
        $expiry = Get-DateTimeFromIso ([string]$_.expiresAt)
        $expiry -gt $now
    })
    if ($kept.Count -ne @(Get-AllSessions).Count) {
        $global:Db.sessions = @($kept)
        return $true
    }
    return $false
}

function Remove-SessionByToken {
    param([string]$Token)
    if ([string]::IsNullOrWhiteSpace($Token)) { return }
    $global:Db.sessions = @(@(Get-AllSessions) | Where-Object { $_.token -ne $Token })
    Save-Database
}

function Remove-AllSessionsForUser {
    param([string]$UserId)
    $global:Db.sessions = @(@(Get-AllSessions) | Where-Object { $_.userId -ne $UserId })
    Save-Database
}

# -------------------------------------------------------------- http cookies --
function Send-SessionCookie {
    param($Response, [string]$Token)
    $maxAge = [int]$global:Config.SessionHours * 3600
    $cookie = '{0}={1}; Path=/; Max-Age={2}; HttpOnly; SameSite=Lax' -f `
        $global:Config.CookieName, $Token, $maxAge
    try { $Response.Headers['Set-Cookie'] = $cookie } catch { }
}

function Clear-SessionCookie {
    param($Response)
    $cookie = '{0}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax' -f $global:Config.CookieName
    try { $Response.Headers['Set-Cookie'] = $cookie } catch { }
}

function Get-RequestCookie {
    param($Request, [string]$Name)
    try {
        $cookie = $Request.Cookies[$Name]
        if ($null -ne $cookie) { return [string]$cookie.Value }
    } catch { }
    return ''
}

# ---------------------------------------------------------------- auth flow --
function Get-AuthContext {
    param($Request)

    $context = @{ User = $null; Session = $null; Token = '' }

    $token = Get-RequestCookie -Request $Request -Name $global:Config.CookieName
    if ([string]::IsNullOrWhiteSpace($token)) { return $context }

    $session = Get-SessionByToken -Token $token
    if ($null -eq $session) { return $context }

    $expiry = Get-DateTimeFromIso ([string]$session.expiresAt)
    if ($expiry -le [DateTime]::UtcNow) {
        Remove-SessionByToken -Token $token
        return $context
    }

    $user = Get-UserById $session.userId
    if ($null -eq $user) {
        Remove-SessionByToken -Token $token
        return $context
    }

    # Deactivated accounts are logged out immediately, even mid-session.
    if ($user.PSObject.Properties.Name -contains 'active' -and -not [bool]$user.active) {
        Remove-SessionByToken -Token $token
        return $context
    }

    $context.User    = $user
    $context.Session = $session
    $context.Token   = $token
    return $context
}

function Start-UserSession {
    param($User, $Response, $Request)

    $session = New-Session -UserId $User.id
    Send-SessionCookie -Response $Response -Token $session.token

    $User | Add-Member -NotePropertyName 'lastLoginAt' -NotePropertyValue (Get-NowIso) -Force
    $User | Add-Member -NotePropertyName 'loginCount'   -NotePropertyValue ([int]$User.loginCount + 1) -Force
    $null = Save-User $User

    $null = Add-ActivityLog -Action 'login' -ActorId $User.id -Detail ('Signed in as ' + $User.role)
    return $session
}

function End-UserSession {
    param($Ctx, $Response)

    if ($null -ne $Ctx.Auth -and -not [string]::IsNullOrWhiteSpace($Ctx.Auth.Token)) {
        Remove-SessionByToken -Token $Ctx.Auth.Token
    }
    Clear-SessionCookie -Response $Response
}

function Get-CsrfToken {
    param($Ctx)
    if ($null -eq $Ctx.Auth -or $null -eq $Ctx.Auth.Session) { return '' }
    return [string]$Ctx.Auth.Session.csrfToken
}

# Visitors who are not signed in have no session yet, so their forms use a
# double-submit token: a random value kept in a cookie and echoed in the form.
# A cross-site attacker can trigger the request but cannot read the cookie.
function Get-AnonymousCsrfToken {
    param($Ctx)

    $existing = Get-RequestCookie -Request $Ctx.Request -Name 'bcr_csrf'
    if (-not [string]::IsNullOrWhiteSpace($existing)) { return $existing }

    $token = ConvertTo-Base64Url (New-RandomBytes -Count 24)
    try {
        $Ctx.Response.Headers['Set-Cookie'] = 'bcr_csrf=' + $token + '; Path=/; Max-Age=43200; HttpOnly; SameSite=Lax'
    } catch { }
    return $token
}

function Test-CsrfToken {
    param($Ctx)
    $expected = Get-CsrfToken -Ctx $Ctx
    $provided = Get-FormValue -Body $Ctx.Body -Name 'csrf_token'
    if ([string]::IsNullOrWhiteSpace($expected)) { return $false }
    if ([string]::IsNullOrWhiteSpace($provided)) { return $false }
    return ($expected -eq $provided)
}

# ------------------------------------------------------------- page guards --
function Protect-Page {
    <#
        Returns $true when the request may continue. Otherwise it emits a
        302 redirect to /login (preserving the intended destination) and
        returns $false. This is what protects every account-only page.
    #>
    param($Ctx)

    if ($null -ne $Ctx.Auth -and $null -ne $Ctx.Auth.User) {
        return $true
    }

    # Use Uri.Query, never QueryString.ToString(): NameValueCollection does not
    # override ToString(), so it always yields
    # "System.Collections.Specialized.NameValueCollection" rather than the
    # actual query text.
    $target = $Ctx.Path
    try {
        $rawQuery = [string]$Ctx.Request.Url.Query
        if (-not [string]::IsNullOrWhiteSpace($rawQuery)) {
            $target = $Ctx.Path + $rawQuery
        }
    } catch { }
    $next = [System.Net.WebUtility]::UrlEncode($target)

    Send-Redirect -Response $Ctx.Response -Location ('/login?next=' + $next) -StatusCode 302
    return $false
}

function Protect-AdminPage {
    param($Ctx)

    if (-not (Protect-Page -Ctx $Ctx)) { return $false }

    if (Test-IsAdmin $Ctx.Auth.User) { return $true }

    Send-Html -Response $Ctx.Response -StatusCode 403 -Html (New-HtmlDocument `
        -Title 'Access denied' -ActiveNav '' -User $Ctx.Auth.User `
        -BodyHtml (New-ErrorBody -StatusCode 403 `
            -Heading 'Administrator access only' `
            -Message 'This page is limited to Barangay administrators. Your account is registered as a regular resident, so you can only view and manage your own reports.'))
    return $false
}

function Test-OwnsComplaint {
    param($Complaint, $User)
    if ($null -eq $Complaint -or $null -eq $User) { return $false }
    if (Test-IsAdmin $User) { return $true }
    return ([string]$Complaint.reporterId -eq [string]$User.id)
}

# ----------------------------------------------------------------- logging --
function Write-AuditLog {
    param($Ctx, [string]$Action, [string]$Detail)
    $actorId = ''
    if ($null -ne $Ctx.Auth -and $null -ne $Ctx.Auth.User) { $actorId = [string]$Ctx.Auth.User.id }
    Add-ActivityLog -Action $Action -ActorId $actorId -Detail $Detail
    Save-Database
}
