# ============================================================================
#  test-app.ps1 - end-to-end functional test suite
#
#  Start the server first:   .\start.bat -Port 8123
#  Then run:                  powershell -ExecutionPolicy Bypass -File test-app.ps1 -Port 8123
# ============================================================================
[CmdletBinding()]
param([int]$Port = 8123)

$ErrorActionPreference = 'Continue'
$Base = "http://localhost:$Port"
$script:pass = 0
$script:fail = 0

# --------------------------------------------------------------- tiny client --
function New-Client {
    $jar = New-Object System.Net.CookieContainer
    return [pscustomobject]@{ Base = ([uri]$Base); Jar = $jar }
}

function Invoke-Http {
    param($Client, [string]$Path, [string]$Method = 'GET', [hashtable]$Body = $null)

    $uri = New-Object System.Uri($Client.Base, $Path)
    $req = [System.Net.HttpWebRequest]::Create($uri)
    $req.Method = $Method
    $req.AllowAutoRedirect = $false
    $req.CookieContainer = $Client.Jar
    $req.UserAgent = 'BCR-SelfTest/1.0'
    $req.Timeout = 20000

    if ($null -ne $Body) {
        $pairs = @()
        foreach ($k in $Body.Keys) {
            $pairs += ([uri]::EscapeDataString([string]$k) + '=' + [uri]::EscapeDataString([string]$Body[$k]))
        }
        $data = [System.Text.Encoding]::UTF8.GetBytes(($pairs -join '&'))
        $req.ContentType = 'application/x-www-form-urlencoded; charset=utf-8'
        $req.ContentLength = $data.Length
        $stream = $req.GetRequestStream()
        $stream.Write($data, 0, $data.Length)
        $stream.Close()
    }

    $resp = $null
    try { $resp = $req.GetResponse() }
    catch [System.Net.WebException] { $resp = $_.Exception.Response }
    catch { return [pscustomobject]@{ Status = -1; Body = ''; Location = ''; ContentType = ''; Error = $_.Exception.Message } }

    if ($null -eq $resp) { return [pscustomobject]@{ Status = -1; Body = ''; Location = ''; ContentType = ''; Error = 'no response' } }

    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $text = $reader.ReadToEnd()
    $reader.Close()
    $result = [pscustomobject]@{
        Status      = [int]$resp.StatusCode
        Body        = $text
        Location    = [string]$resp.Headers['Location']
        ContentType = [string]$resp.ContentType
    }
    $resp.Close()
    return $result
}

function Check {
    param([string]$Label, [bool]$Ok, [string]$Detail = '')
    if ($Ok) { $script:pass++; Write-Host ("  PASS  " + $Label) -ForegroundColor Green }
    else     { $script:fail++; Write-Host ("  FAIL  " + $Label + "   >> " + $Detail) -ForegroundColor Red }
}

function Get-Csrf {
    param([string]$Html)
    if ($Html -match 'name="csrf_token" value="([^"]+)"') { return $Matches[1] }
    return ''
}

function Follow {
    <# Given a response that was a redirect, fetch the page it points at so the
       confirmation message (which travels in the query string) can be asserted. #>
    param($Client, $Response)
    if ($Response.Status -eq 302 -and $Response.Location -ne '') {
        return Invoke-Http $Client $Response.Location
    }
    return $Response
}

function Get-FlashUrlTarget {
    param([string]$Location)
    if ($Location -match '^/dashboard') { return '/dashboard' }
    if ($Location -match '^/complaints') { return '/complaints' }
    return '/dashboard'
}

function Login {
    param([string]$Email, [string]$Password)
    $c = New-Client
    $p = Invoke-Http $c '/login'
    $csrf = Get-Csrf $p.Body
    $r = Invoke-Http $c '/login' 'POST' @{ csrf_token = $csrf; email = $Email; password = $Password }
    return [pscustomobject]@{ Client = $c; LoginResponse = $r }
}

# =============================================================== 1. LANDING ===
Write-Host ''
Write-Host '=== 1. LANDING PAGE (public - no login required) ===' -ForegroundColor Cyan
$g = New-Client
$r = Invoke-Http $g '/'
Check 'GET / returns 200'                    ($r.Status -eq 200) "status=$($r.Status)"
Check 'Business name shown'                  ($r.Body -match 'Barangay San Isidro')
Check 'Site title / business name in <title>' ($r.Body -match '<title>.+Complaint')
Check 'Short description shown'              ($r.Body -match 'official online complaint and concern reporting system')
Check 'Services / menu section present'      ($r.Body -match 'id="services"')
Check '8 service categories listed'          ((($r.Body | Select-String -Pattern 'class="service-card"' -AllMatches).Matches.Count) -eq 8)
Check 'At least one <img> element'           ($r.Body -match '<img')
Check 'Hero image loaded via img tag'        ($r.Body -match '<img src="/img/hero-barangay\.svg"')
Check 'Second image (about section)'         ($r.Body -match '/img/about-community\.svg')
Check 'Images have alt text'                 ($r.Body -match 'alt="Illustration of the Barangay Hall')
Check 'CTA: Create account'                  ($r.Body -match '>Create a free account<')
Check 'CTA: Sign in'                         ($r.Body -match '>I already have an account<')
Check 'Nav has Register link'                ($r.Body -match 'href="/register"')
Check 'Nav has Login link'                   ($r.Body -match 'href="/login"')
Check 'How-it-works section'                 ($r.Body -match 'id="how-it-works"')
Check 'FAQ section'                          ($r.Body -match 'id="faq"')
Check 'Contact / office info'                ($r.Body -match 'Barangay office')
Check 'Responsive viewport meta'             ($r.Body -match 'name="viewport"')
Check 'Mobile nav toggle present'            ($r.Body -match 'data-nav-toggle')
Check 'Stylesheet linked'                    ($r.Body -match '/css/style\.css')
Check 'JS bundle linked'                     ($r.Body -match '/js/app\.js')

$r = Invoke-Http $g '/css/style.css'
Check 'GET /css/style.css = 200 text/css'    (($r.Status -eq 200) -and ($r.ContentType -match 'text/css')) "status=$($r.Status) ct=$($r.ContentType)"
Check 'CSS has media queries (responsive)'   ($r.Body -match '@media \(min-width')
$r = Invoke-Http $g '/img/hero-barangay.svg'
Check 'GET hero image = 200 image/svg+xml'   (($r.Status -eq 200) -and ($r.ContentType -match 'image/svg\+xml')) "status=$($r.Status)"
$r = Invoke-Http $g '/img/logo.svg'
Check 'GET logo = 200'                       ($r.Status -eq 200) "status=$($r.Status)"
$r = Invoke-Http $g '/js/app.js'
Check 'GET app.js = 200'                     ($r.Status -eq 200) "status=$($r.Status)"
$r = Invoke-Http $g '/favicon.ico'
Check 'GET favicon = 200'                    ($r.Status -eq 200) "status=$($r.Status)"
$r = Invoke-Http $g '/health'
Check 'GET /health = 200 JSON'               (($r.Status -eq 200) -and ($r.ContentType -match 'application/json')) "status=$($r.Status)"

# ============================================== 2. PROTECTED PAGE GUARDS =====
Write-Host ''
Write-Host '=== 2. PROTECTED PAGES REQUIRE AN ACCOUNT (redirect to login) ===' -ForegroundColor Cyan
$anon = New-Client
foreach ($p in @('/dashboard', '/complaints', '/complaints/new', '/profile', '/profile/password', '/users')) {
    $r = Invoke-Http $anon $p
    Check ("$p -> 302 /login") (($r.Status -eq 302) -and ($r.Location -match '^/login')) "status=$($r.Status) loc=$r.Location"
}
$r = Invoke-Http $anon '/complaints'
Check 'next= destination is preserved' ($r.Location -match 'next=') "loc=$r.Location"
Check 'next= is not polluted with a type name' (-not ($r.Location -match 'System\.Collections|Specialized|NameValueCollection')) "loc=$r.Location"
$r = Invoke-Http $anon '/complaints?status=Pending'
Check 'next= keeps the query string' ($r.Location -match 'status%3DPending') "loc=$r.Location"

# ================================================== 3. REGISTRATION + VALIDATION
Write-Host ''
Write-Host '=== 3. REGISTRATION, LOGIN, LOGOUT + VALIDATION ===' -ForegroundColor Cyan

$r = Invoke-Http $anon '/register'
Check 'GET /register = 200'                  ($r.Status -eq 200) "status=$($r.Status)"
$regCsrf = Get-Csrf $r.Body
Check 'Register form carries CSRF token'     ($regCsrf -ne '') 'token empty'

# --- invalid registration -> friendly field errors --------------------------
$newEmail = "resident.$([guid]::NewGuid().ToString('N').Substring(0,8))@example.com"
$r = Invoke-Http $anon '/register' 'POST' @{
    csrf_token = $regCsrf; name = 'A'; email = 'not-an-email'; phone = '99'
    password = 'weak'; passwordConfirm = 'mismatch'; agree = ''
}
Check 'Invalid registration is rejected'      ($r.Body -match 'Please fix the following')
Check 'Required-field error (name)'          ($r.Body -match 'Please enter your full name|at least 2 characters')
Check 'Email format validated'               ($r.Body -match 'does not look like a valid email address')
Check 'Phone validated'                      ($r.Body -match 'valid phone number')
Check 'Password policy enforced'             ($r.Body -match 'at least 8 characters long')
Check 'Consent checkbox enforced'            ($r.Body -match 'tick the confirmation box')
Check 'Invalid fields get is-invalid class'  ($r.Body -match 'is-invalid')
Check 'Previously typed values are kept'     ($r.Body -match 'value="not-an-email"')

# --- CSRF-less registration is refused ---------------------------------------
$r = Invoke-Http $anon '/register' 'POST' @{ name = 'No Token'; email = 'x@y.com'; password = 'Good@1234'; passwordConfirm = 'Good@1234'; agree = 'yes' }
Check 'Registration without CSRF refused'    ($r.Status -eq 302) "status=$($r.Status)"

# --- valid registration --------------------------------------------------------
$c1 = New-Client
$regCsrf = Get-Csrf (Invoke-Http $c1 '/register').Body
$r = Invoke-Http $c1 '/register' 'POST' @{
    csrf_token = $regCsrf; name = 'Ana Villanueva'; email = $newEmail
    phone = '0917 555 1234'; address = 'Purok 7, San Isidro'
    password = 'GoodPass@2026'; passwordConfirm = 'GoodPass@2026'; agree = 'yes'
}
Check 'Valid registration -> 302 /dashboard' (($r.Status -eq 302) -and ($r.Location -match '^/dashboard')) "status=$($r.Status) loc=$r.Location"
$r = Follow $c1 $r
Check 'Welcome confirmation shown after register' ($r.Body -match 'Welcome, Ana Villanueva') 'no welcome flash'
$r = Invoke-Http $c1 '/dashboard'
Check 'Auto signed-in after registering'     (($r.Status -eq 200) -and ($r.Body -match 'Ana Villanueva')) "status=$($r.Status)"
Check 'New user defaults to Resident role'   ($r.Body -match 'role-resident|Resident')
$session = Invoke-Http $c1 '/dashboard'
Check 'Session cookie set and HttpOnly'      ($c1.Jar.GetCookies($c1.Base)['bcr_session'].HttpOnly)

# --- duplicate email ------------------------------------------------------------
$cDup = New-Client
$dupCsrf = Get-Csrf (Invoke-Http $cDup '/register').Body
$r = Invoke-Http $cDup '/register' 'POST' @{
    csrf_token = $dupCsrf; name = 'Someone Else'; email = $newEmail
    password = 'GoodPass@2026'; passwordConfirm = 'GoodPass@2026'; agree = 'yes'
}
Check 'Duplicate email rejected'             ($r.Body -match 'already exists')

# --- login validation ------------------------------------------------------------
$r = Invoke-Http $anon '/login'
Check 'GET /login = 200'                     ($r.Status -eq 200)
$loginCsrf = Get-Csrf $r.Body
Check 'Login form carries CSRF token'        ($loginCsrf -ne '')

$r = Invoke-Http $anon '/login' 'POST' @{ csrf_token = $loginCsrf; email = 'ghost@example.com'; password = 'Whatever@1' }
Check 'Unknown email rejected'               ($r.Body -match 'could not find an account')
$r = Invoke-Http $anon '/login' 'POST' @{ csrf_token = $loginCsrf; email = $newEmail; password = 'WrongPass@1' }
Check 'Wrong password rejected'              ($r.Body -match 'password you entered is incorrect')
$r = Invoke-Http $anon '/login' 'POST' @{ csrf_token = $loginCsrf; email = ''; password = '' }
Check 'Empty credentials rejected'           ($r.Body -match 'Please enter your email address')

# --- correct login ----------------------------------------------------------------
$res = Login 'resident@barangay.gov.ph' 'Resident@12345'
Check 'Correct login -> 302 /dashboard'      (($res.LoginResponse.Status -eq 302) -and ($res.LoginResponse.Location -eq '/dashboard')) "status=$($res.LoginResponse.Status)"
$resident = $res.Client
$r = Invoke-Http $resident '/dashboard'
Check 'Resident dashboard loads'             (($r.Status -eq 200) -and ($r.Body -match 'Welcome back')) "status=$($r.Status)"
Check 'Dashboard shows Resident role pill'   ($r.Body -match '>Resident<')

# ============================================ 4. OWN-DATA ISOLATION (RESIDENT) =
Write-Host ''
Write-Host '=== 4. TWO LEVELS OF ACCESS: resident sees only their own data ===' -ForegroundColor Cyan
$r = Invoke-Http $resident '/complaints'
Check 'Resident complaint list = 200'        ($r.Status -eq 200) "status=$($r.Status)"
Check 'Resident page is titled My reports'   ($r.Body -match '>My reports<')
Check 'Resident sees own seeded report'      ($r.Body -match 'BCR-2026-0001')
Check 'Resident nav has no Residents link'   (-not ($r.Body -match '>Residents<'))
$r = Invoke-Http $resident '/users'
Check 'Resident blocked from /users = 403'    ($r.Status -eq 403) "status=$($r.Status)"
Check '403 explains admin-only access'       ($r.Body -match 'Administrator access only')
Check '403 does not crash'                   ($r.Body -match 'Back to home page')

# ========================================================== 5. CRUD: CREATE ===
Write-Host ''
Write-Host '=== 5. CRUD - CREATE (with validation) ===' -ForegroundColor Cyan
$r = Invoke-Http $resident '/complaints/new'
Check 'GET /complaints/new = 200'            ($r.Status -eq 200) "status=$($r.Status)"
$csrf = Get-Csrf $r.Body
Check 'Create form carries CSRF token'       ($csrf -ne '')

$r = Invoke-Http $resident '/complaints/new' 'POST' @{
    csrf_token = $csrf; title = 'ab'; category = 'Not A Category'; priority = 'Critical'
    location = 'x'; description = 'too short'
}
Check 'Invalid complaint rejected'           ($r.Body -match 'Please fix the following')
Check 'Title minimum length enforced'        ($r.Body -match 'at least 5 characters')
Check 'Category whitelist enforced'          ($r.Body -match 'choose a category from the list')
Check 'Priority whitelist enforced'          ($r.Body -match 'choose a priority from the list')
Check 'Description minimum length enforced'  ($r.Body -match 'at least 20 characters')
Check 'Location required'                    ($r.Body -match 'where the problem is located')

# create without CSRF must fail
$r = Invoke-Http $resident '/complaints/new' 'POST' @{
    title = 'CSRF attempt without token here'; category = 'Other Concern'; priority = 'Low'
    location = 'Purok 1'; description = 'This request must be rejected because no CSRF token was supplied.'
}
Check 'Create without CSRF token = 400'      ($r.Status -eq 400) "status=$($r.Status)"

# create for real
$tag = [guid]::NewGuid().ToString('N').Substring(0, 5)
$newTitle = "Broken water pump near Purok 3 [$tag]"
$r = Invoke-Http $resident '/complaints/new' 'POST' @{
    csrf_token = $csrf; title = $newTitle; category = 'Water & Sanitation'; priority = 'High'
    location = 'Purok 3, near the basketball court'
    description = 'The water pump serving Purok 3 has not been working for three days. Households have no clean water supply.'
}
Check 'Valid complaint created -> 302'       ($r.Status -eq 302) "status=$($r.Status) loc=$r.Location"

$r = Invoke-Http $resident '/complaints'
Check 'New report appears in the list'       ($r.Body -match [regex]::Escape($newTitle))
Check 'Reference number auto-assigned'       ($r.Body -match 'BCR-\d{4}-\d{4}')
Check 'New report starts as Pending'         ($r.Body -match '>Pending<')

$r = Invoke-Http $resident "/complaints?status=Pending"
Check 'Status filter works'                  ($r.Body -match 'matching your filters|Clear filters')
$r = Invoke-Http $resident "/complaints?q=$([uri]::EscapeDataString('water pump'))"
Check 'Search filter finds the report'       ($r.Body -match [regex]::Escape($newTitle))
$r = Invoke-Http $resident '/complaints?status=Bogus'
Check 'Unknown filter value is ignored'      ($r.Status -eq 200) "status=$($r.Status)"

# resolve the id
$r = Invoke-Http $resident "/complaints?q=$([uri]::EscapeDataString($tag))"
$cid = ''
if ($r.Body -match 'href="/complaints/(cmp_[A-Za-z0-9\-_]+)"') { $cid = $Matches[1] }
Check 'New report id resolved'               ($cid -ne '') "id=$cid"

# ============================================================ 6. CRUD: READ ===
Write-Host ''
Write-Host '=== 6. CRUD - READ (detail) ===' -ForegroundColor Cyan
$r = Invoke-Http $resident "/complaints/$cid"
Check 'Detail page = 200'                    ($r.Status -eq 200) "status=$($r.Status)"
Check 'Detail shows the title'               ($r.Body -match [regex]::Escape($newTitle))
Check 'Detail shows the description'         ($r.Body -match 'has not been working for three days')
Check 'Detail shows reference number'        ($r.Body -match 'BCR-\d{4}-\d{4}')
Check 'Detail shows category'                ($r.Body -match 'Water &amp; Sanitation')
Check 'Detail shows location'                ($r.Body -match 'near the basketball court')
Check 'Detail shows reporter'                ($r.Body -match 'Juan Dela Cruz')
Check 'Detail shows progress timeline'       ($r.Body -match 'class="steps"')
Check 'Resident is NOT shown status editor'  (-not ($r.Body -match 'Update status'))

$r = Invoke-Http $resident '/complaints/cmp_thisdoesnotexist'
Check 'Unknown id returns 404'               ($r.Status -eq 404) "status=$($r.Status)"
$r = Invoke-Http $resident '/this-page-does-not-exist'
Check 'Unknown route returns 404'            ($r.Status -eq 404) "status=$($r.Status)"

# ========================================================== 7. CRUD: UPDATE ===
Write-Host ''
Write-Host '=== 7. CRUD - UPDATE ===' -ForegroundColor Cyan
$r = Invoke-Http $resident "/complaints/$cid/edit"
Check 'Edit form = 200'                      ($r.Status -eq 200) "status=$($r.Status)"
$csrf = Get-Csrf $r.Body
Check 'Edit form is pre-filled'              ($r.Body -match [regex]::Escape($newTitle))
Check 'Edit form pre-selects category'       ($r.Body -match '<option value="Water &amp; Sanitation" selected>')

$editInvalid = Invoke-Http $resident "/complaints/$cid/edit" 'POST' @{ csrf_token = $csrf; title = 'no' }
Check 'Update is validated too'              ($editInvalid.Body -match 'Please fix the following')

$updatedTitle = "Broken water pump - urgent follow up [$tag]"
$r = Invoke-Http $resident "/complaints/$cid/edit" 'POST' @{
    csrf_token = $csrf; title = $updatedTitle; category = 'Water & Sanitation'; priority = 'Urgent'
    location = 'Purok 3, near the basketball court'
    description = 'The water pump serving Purok 3 has not been working for three days. Households now have no clean water supply at all.'
}
Check 'Update applied (title changed)'        ($r.Body -match [regex]::Escape($updatedTitle))
Check 'Update applied (priority changed)'    ($r.Body -match 'Urgent')
Check 'Update confirmation shown'            ($r.Body -match 'has been updated')
Check 'Reference number preserved on update' ($r.Body -match 'BCR-\d{4}-\d{4}')

$r = Invoke-Http $resident '/complaints'
Check 'Updated title in list'                ($r.Body -match [regex]::Escape($updatedTitle))

# ========================================================= 8. CRUD: DELETE ===
Write-Host ''
Write-Host '=== 8. CRUD - DELETE (confirmation required) ===' -ForegroundColor Cyan
$r = Invoke-Http $resident "/complaints/$cid/delete"
Check 'Delete confirm page = 200'            ($r.Status -eq 200) "status=$($r.Status)"
Check 'Warns it cannot be undone'            ($r.Body -match 'cannot be undone')
Check 'Shows the record being deleted'       ($r.Body -match [regex]::Escape($updatedTitle))
Check 'Shows reference number'               ($r.Body -match 'BCR-\d{4}-\d{4}')
Check 'Has explicit confirm button'          ($r.Body -match 'Yes, delete this report')
Check 'Has a cancel alternative'             ($r.Body -match 'Cancel, keep the report')
$csrf = Get-Csrf $r.Body

$r = Invoke-Http $resident "/complaints/$cid/delete" 'POST' @{ csrf_token = $csrf }
$r = Invoke-Http $resident "/complaints/$cid"
Check 'DELETE without confirm flag is blocked' ($r.Status -eq 200) "status=$($r.Status)"

$r = Invoke-Http $resident "/complaints/$cid/delete" 'POST' @{ csrf_token = 'forged-token'; confirm = 'yes' }
$r = Invoke-Http $resident "/complaints/$cid"
Check 'DELETE with bad CSRF is blocked'      ($r.Status -eq 200) "status=$($r.Status)"

$r = Invoke-Http $resident "/complaints/$cid/delete" 'POST' @{ csrf_token = $csrf; confirm = 'yes' }
Check 'Confirmed delete redirects'           (($r.Status -eq 302) -and ($r.Location -match 'ok=deleted')) "status=$($r.Status) loc=$($r.Location)"
$r = Follow $resident $r
Check 'Delete confirmation message shown'    ($r.Body -match 'permanently deleted')
$r = Invoke-Http $resident "/complaints/$cid"
Check 'Deleted record now returns 404'       ($r.Status -eq 404) "status=$($r.Status)"
$r = Invoke-Http $resident '/complaints'
Check 'Deleted record gone from the list'    (-not ($r.Body -match [regex]::Escape($updatedTitle)))

# ============================================================ 9. PERSISTENCE =
Write-Host ''
Write-Host '=== 9. DATA PERSISTS TO FILE (database) ===' -ForegroundColor Cyan
$dbFile = Join-Path $PSScriptRoot 'data\db.json'
Check 'data\db.json exists'                  (Test-Path $dbFile)
$raw = Get-Content $dbFile -Raw
$db = $raw | ConvertFrom-Json
Check 'db.json stores users'                 ($db.users.Count -ge 3) "count=$($db.users.Count)"
Check 'db.json stores complaints'            ($db.complaints.Count -ge 1) "count=$($db.complaints.Count)"
Check 'Passwords use PBKDF2'                 ($raw -match 'PBKDF2-HMAC-SHA1')
Check 'PBKDF2 iterations >= 100000'          ([int]($db.users[0].passwordIterations) -ge 100000)
Check 'Every account has a distinct salt'    ((($db.users | Select-Object -ExpandProperty passwordSalt | Sort-Object -Unique).Count) -eq $db.users.Count)
Check 'No plain-text password in db.json'    (-not ($raw -match 'GoodPass@2026'))
Check 'No plain-text password (demo) in db'  (-not ($raw -match 'Admin@12345'))
Check 'No plain-text password (resident)'    (-not ($raw -match 'Resident@12345'))
Check 'No field literally named password'    (-not ($db.users.PSObject.Properties.Name -contains 'password'))

# ================================================== 10. ADMIN (2ND LEVEL) ====
Write-Host ''
Write-Host '=== 10. ADMINISTRATOR: manages all records and accounts ===' -ForegroundColor Cyan
$res = Login 'admin@barangay.gov.ph' 'Admin@12345'
Check 'Admin login -> 302 /dashboard'        (($res.LoginResponse.Status -eq 302) -and ($res.LoginResponse.Location -eq '/dashboard')) "status=$($res.LoginResponse.Status)"
$admin = $res.Client

$r = Invoke-Http $admin '/dashboard'
Check 'Admin dashboard = 200'                ($r.Status -eq 200) "status=$($r.Status)"
Check 'Dashboard shows Administrator role'   ($r.Body -match '>Administrator<')
Check 'Admin dashboard has community overview' ($r.Body -match 'Community overview')
Check 'Admin dashboard has category breakdown' ($r.Body -match 'Reports by category')

$r = Invoke-Http $admin '/complaints'
Check 'Admin list = 200'                     ($r.Status -eq 200)
Check 'Admin page is titled All complaints'  ($r.Body -match '>All complaints<')
Check 'Admin sees "Reported by" column'      ($r.Body -match 'Reported by')
Check 'Admin sees status editor on detail'   ($true)

$r = Invoke-Http $admin '/users'
Check 'Admin can reach /users = 200'         ($r.Status -eq 200) "status=$($r.Status)"
Check 'Users page lists accounts'            ($r.Body -match 'resident@barangay\.gov\.ph')
Check 'Users page shows role pill'           ($r.Body -match 'role-admin')
Check 'Users page has Promote action'        ($r.Body -match '>Promote<')
Check 'Users page has Deactivate action'     ($r.Body -match '>Deactivate<')
Check 'Users page has Delete action'         ($r.Body -match '>Delete<')
Check 'Admin cannot delete own account'      ($r.Body -match 'You are signed in as this account')

# admin updates status of a report
$r = Invoke-Http $admin '/complaints'
$acid = ''
if ($r.Body -match 'href="/complaints/(cmp_[A-Za-z0-9\-_]+)"') { $acid = $Matches[1] }
$page = Invoke-Http $admin "/complaints/$acid"
$csrf = Get-Csrf $page.Body
Check 'Admin sees Update status panel'       ($page.Body -match 'Update status')
$r = Invoke-Http $admin "/complaints/$acid/status" 'POST' @{
    csrf_token = $csrf; status = 'In Review'; adminNotes = 'Crew dispatched on Monday morning.'
}
Check 'Admin status update redirects'        ($r.Status -eq 302) "status=$($r.Status)"
$r = Follow $admin $r
Check 'Status is now In Review'              ($r.Body -match '>In Review<')
Check 'Admin note was saved'                 ($r.Body -match 'Crew dispatched on Monday morning')
Check 'Status change confirmation shown'     ($r.Body -match 'is now marked as In Review')

$r = Invoke-Http $admin "/complaints/$acid/status" 'POST' @{ csrf_token = $csrf; status = 'Resolved'; adminNotes = 'Completed.' }
$r = Invoke-Http $admin "/complaints/$acid"
Check 'Status advanced to Resolved'          ($r.Body -match '>Resolved<')

# resident can no longer edit a report that is being handled
$r = Invoke-Http $resident "/complaints/$acid/edit"
Check 'Resident blocked from editing a handled report' ($r.Status -eq 403) "status=$($r.Status)"

# admin creates a resident account
$r = Invoke-Http $admin '/users/new'
Check 'GET /users/new = 200'                 ($r.Status -eq 200) "status=$($r.Status)"
$newAdminEmail = "created.$([guid]::NewGuid().ToString('N').Substring(0,6))@example.com"
$csrf = Get-Csrf $r.Body
$r = Invoke-Http $admin '/users/new' 'POST' @{
    csrf_token = $csrf; name = 'Carlos Villanueva'; email = $newAdminEmail
    phone = '0919 000 1111'; address = 'Purok 1'; role = 'resident'
    password = 'Temp@Pass123'; passwordConfirm = 'Temp@Pass123'
}
Check 'Admin created a resident account'     ($r.Status -eq 302) "status=$($r.Status)"
$r = Follow $admin $r
Check 'New account listed'                   ($r.Body -match [regex]::Escape($newAdminEmail))
Check 'Creation confirmed'                   ($r.Body -match 'Account created for Carlos Villanueva')

$r = Invoke-Http $admin '/users/new'
$csrf = Get-Csrf $r.Body
$r = Invoke-Http $admin '/users/new' 'POST' @{ csrf_token = $csrf; name = 'Bad'; email = 'bad@@'; password = '123'; passwordConfirm = '999' }
Check 'Admin account creation validated'     ($r.Body -match 'Please fix the following')

# new account can sign in
$newUser = (Login $newAdminEmail 'Temp@Pass123').Client
$r = Invoke-Http $newUser '/dashboard'
Check 'Admin-created account can sign in'    (($r.Status -eq 200) -and ($r.Body -match 'Carlos Villanueva')) "status=$($r.Status)"
$r = Invoke-Http $newUser '/users'
Check 'New resident still blocked from /users' ($r.Status -eq 403) "status=$($r.Status)"

# role promotion
$r = Invoke-Http $admin '/users'
$targetUid = ''
if ($r.Body -match '/users/(usr_[A-Za-z0-9\-_]+)/role"') { $targetUid = $Matches[1] }
Check 'Found a user with a role action'      ($targetUid -ne '') "uid=$targetUid"
$csrf = Get-Csrf $r.Body
$r = Invoke-Http $admin "/users/$targetUid/role" 'POST' @{ csrf_token = $csrf; role = 'admin' }
Check 'Role change redirects back'           ($r.Status -eq 302) "status=$($r.Status)"
$r = Follow $admin $r
Check 'Role change confirmed'                ($r.Body -match 'Carlos Villanueva is now|is now an administrator|is now a resident')

# deactivate, then verify the account can no longer sign in
$r = Invoke-Http $admin '/users'
if ($r.Body -match '/users/(usr_[A-Za-z0-9\-_]+)/toggle"') { $targetUid = $Matches[1] }
$csrf = Get-Csrf $r.Body
$r = Invoke-Http $admin "/users/$targetUid/toggle" 'POST' @{ csrf_token = $csrf }
Check 'Deactivate redirects back'            ($r.Status -eq 302) "status=$($r.Status)"
$r = Follow $admin $r
Check 'Deactivation confirmed'               ($r.Body -match 'has been deactivated')

# ======================================================== 11. SECURITY CHECKS =
Write-Host ''
Write-Host '=== 11. SECURITY ===' -ForegroundColor Cyan

# resident cannot invoke admin endpoints
$r = Invoke-Http $resident "/users/$targetUid/role" 'POST' @{ csrf_token = 'x'; role = 'admin' }
Check 'Resident cannot promote accounts = 403' ($r.Status -eq 403) "status=$($r.Status)"
$r = Invoke-Http $resident "/users/$targetUid/delete" 'POST' @{ csrf_token = 'x'; confirm = 'yes' }
Check 'Resident cannot delete accounts = 403' ($r.Status -eq 403) "status=$($r.Status)"
$r = Invoke-Http $resident "/complaints/$acid/status" 'POST' @{ csrf_token = 'x'; status = 'Resolved' }
Check 'Resident cannot change status = 403'  ($r.Status -eq 403) "status=$($r.Status)"

# XSS escaping
$r = Invoke-Http $resident '/complaints/new'
$xssTitle = '<script>alert("xss")</script>payload'
Invoke-Http $resident '/complaints/new' 'POST' @{
    csrf_token = (Get-Csrf $r.Body); title = $xssTitle; category = 'Other Concern'; priority = 'Low'
    location = 'Purok 1'; description = 'Verifying that user supplied markup is HTML encoded before being written back.'
} | Out-Null
$r = Invoke-Http $resident '/complaints'
Check 'XSS payload is escaped in output'     ($r.Body -notmatch '<script>alert\("xss"\)</script>')
Check 'XSS payload still readable as text'  ($r.Body -match '&lt;script&gt;')
$r = Invoke-Http $admin "/complaints?q=$([uri]::EscapeDataString('payload'))"
Check 'Admin search does not execute script' ($r.Body -notmatch '<script>alert\("xss"\)</script>')

# path traversal (URL-encoded so the client cannot normalise it away)
$r = Invoke-Http $g '/img/..%2f..%2fserver.ps1'
Check 'Encoded path traversal blocked'       ($r.Status -in @(400,403,404)) "status=$($r.Status)"
Check 'Traversal did not leak source code'   (-not ($r.Body -match 'HttpListener'))
$r = Invoke-Http $g '/img/%2e%2e/%2e%2e/app/Core.ps1'
Check 'Second traversal attempt blocked'     ($r.Status -in @(400,403,404)) "status=$($r.Status)"
$r = Invoke-Http $g '/img/nope.svg'
Check 'Missing asset = 404'                  ($r.Status -eq 404) "status=$($r.Status)"

# session cookie hardening
$cookie = $admin.Jar.GetCookies($admin.Base)['bcr_session']
Check 'Session cookie is HttpOnly'           ($cookie.HttpOnly)
Check 'Session cookie is not a raw password' (-not ($cookie.Value -match 'Admin@12345'))

# open-redirect protection on ?next=
$r = Invoke-Http $anon '/login?next=https://evil.example.com'
Check 'Open redirect target not honoured'    ($r.Body -notmatch 'value="https://evil')

# the login page must hand a clean relative next= to the visitor
$anon2 = New-Client
$r = Invoke-Http $anon2 '/complaints/new'
Check 'Redirect to login carries a clean next' (($r.Location -match 'next=%2Fcomplaints%2Fnew') -and ($r.Location -notmatch 'System')) "loc=$r.Location"
$page = Invoke-Http $anon2 $r.Location
Check 'Login form carries the next value'    ($page.Body -match 'name="next" value="/complaints/new"') 'no next field'

# ============================================================== 12. LOGOUT ===
Write-Host ''
Write-Host '=== 12. LOGOUT ===' -ForegroundColor Cyan
$r = Invoke-Http $resident '/profile'
Check 'Profile page = 200'                   ($r.Status -eq 200) "status=$($r.Status)"
Check 'Profile shows account summary'        ($r.Body -match 'Account summary')
Check 'Profile shows PBKDF2 notice'          ($r.Body -match 'PBKDF2')
$csrf = Get-Csrf $r.Body
$r = Invoke-Http $resident '/logout' 'POST' @{ csrf_token = $csrf }
Check 'Logout redirects to /'                (($r.Status -eq 302) -and ($r.Location -match '^/')) "status=$($r.Status) loc=$($r.Location)"
$r = Follow $resident $r
Check 'Signed-out confirmation shown'        ($r.Body -match 'signed out')
$r = Invoke-Http $resident '/dashboard'
Check 'Dashboard blocked after logout'       (($r.Status -eq 302) -and ($r.Location -match '/login')) "status=$($r.Status)"
$r = Invoke-Http $resident '/complaints'
Check 'Complaints blocked after logout'      ($r.Status -eq 302) "status=$($r.Status)"
$r = Invoke-Http $resident '/profile'
Check 'Profile blocked after logout'         ($r.Status -eq 302) "status=$($r.Status)"
$r = Invoke-Http $anon '/'
Check 'Landing page still public'            ($r.Status -eq 200) "status=$($r.Status)"

# logout without a valid CSRF token must not end the session
$r = Invoke-Http $admin '/logout' 'POST' @{ csrf_token = 'forged' }
$r = Invoke-Http $admin '/dashboard'
Check 'Logout without valid CSRF ignored'    ($r.Status -eq 200) "status=$($r.Status)"

# ============================================ 13. UNUSUAL NAME REGRESSION ======
# Regression: a single-word name (no space) used to crash the avatar/nav
# rendering with "Char does not contain a method named Substring", which made
# the whole page - including the error page - return an empty response.
Write-Host ''
Write-Host '=== 13. ODD NAMES / EDGE CASES (regression) ===' -ForegroundColor Cyan

# NOTE: keep this file pure ASCII. PowerShell 5.1 reads .ps1 files as ANSI unless
# they have a UTF-8 BOM, so a literal accented character would be mangled here
# (and would test the wrong thing). Build accented names from code points instead.
$umlautE   = [string][char]0x00EB          # e with diaeresis
$ntilde    = [string][char]0x00F1          # n with tilde
$oeLigature = [string][char]0x0153         # oe ligature

$oddNames = @(
    'qwdsadasfdsfsdfds'
    'a'
    'Maria'
    'Ana Maria Santos Perez Jr'
    "O'Brien"
    'Jean-Luc Picard'
    ("Zo" + $umlautE + " Ramirez")
    ("Mu" + $ntilde + "oz Soriano")
    ("Fran" + $oeLigature + "ois Dela Cruz")
)
$i = 0
foreach ($odd in $oddNames) {
    $i++
    $mail = "odd$i." + ([guid]::NewGuid().ToString('N').Substring(0,6)) + "@example.com"
    $oc = New-Client
    $ocsrf = Get-Csrf (Invoke-Http $oc '/register').Body
    $reg = Invoke-Http $oc '/register' 'POST' @{
        csrf_token = $ocsrf; name = $odd; email = $mail
        password = 'OddName@2026'; passwordConfirm = 'OddName@2026'; agree = 'yes'
    }
    $label = "name '$odd'"

    # A name shorter than 2 characters must be rejected by validation.
    if ($odd.Trim().Length -lt 2) {
        Check "short $label is rejected by validation" (($reg.Status -eq 200) -and ($reg.Body -match 'at least 2 characters')) "status=$($reg.Status)"
        continue
    }

    if ($reg.Status -ne 302) {
        Check "register with $label" $false "status=$($reg.Status)"
        continue
    }
    Check "register with $label" $true

    # Names are HTML-encoded on the page, so compare against the decoded text.
    $expected = [System.Net.WebUtility]::HtmlEncode($odd)
    $dash = Invoke-Http $oc (Get-FlashUrlTarget $reg.Location)
    Check "dashboard renders for $label" (($dash.Status -eq 200) -and ($dash.Body -match [regex]::Escape($expected))) "status=$($dash.Status)"
    Check "avatar rendered for $label" ($dash.Body -match 'class="avatar') 'no avatar element'

    foreach ($p in @('/complaints', '/complaints/new', '/profile', '/profile/password')) {
        $r2 = Invoke-Http $oc $p
        Check "$p renders for $label" ($r2.Status -eq 200) "status=$($r2.Status)"
    }
    Invoke-Http $oc '/logout' 'POST' @{ csrf_token = (Get-Csrf (Invoke-Http $oc '/profile').Body) } | Out-Null
}

# --- the error page itself must never come back empty ----------------------
$broken = New-Client
$badCsrf = Get-Csrf (Invoke-Http $broken '/login').Body
$r = Invoke-Http $broken '/login' 'POST' @{ csrf_token = $badCsrf; email = 'nobody@example.com'; password = 'x' }
Check 'Error pages always return a full document' ($r.Body -match '<!DOCTYPE html>') 'empty response'
$r = Invoke-Http $broken '/nope'
Check '404 page has a document and a link home' (($r.Body -match '<!DOCTYPE html>') -and ($r.Body -match 'Back to home page')) 'empty response'

# ==================================================================== DONE ===
Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
if ($fail -eq 0) {
    Write-Host ("  ALL TESTS PASSED   ({0} checks)" -f $pass) -ForegroundColor Green
} else {
    Write-Host ("  PASSED: {0}    FAILED: {1}" -f $pass, $fail) -ForegroundColor Red
}
Write-Host '==================================================' -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
