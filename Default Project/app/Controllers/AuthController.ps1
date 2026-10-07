# ============================================================================
#  Controllers/AuthController.ps1 - Register, Login, Logout, Profile
# ============================================================================

function Invoke-ShowLogin {
    param($Ctx)

    # Already signed in? Skip the form.
    if ($null -ne $Ctx.Auth.User) {
        Send-Redirect -Response $Ctx.Response -Location '/dashboard'
        return
    }

    $next = Get-QueryValue -Request $Ctx.Request -Name 'next'
    # Only allow same-site relative redirects (blocks open-redirect tricks)
    if (-not (Test-SafeRedirect $next)) { $next = '' }

    $errors = $Ctx.Errors
    $values = @{
        email = [string]$Ctx.FormData['email']
        next  = $next
    }

    $anonCsrf = Get-AnonymousCsrfToken -Ctx $Ctx

    $nextInput = ''
    if (-not [string]::IsNullOrWhiteSpace($next)) {
        $nextInput = '<input type="hidden" name="next" value="' + (HtmlEncode $next) + '">'
    }

    $body = @"
<section class="auth-shell">
  <div class="auth-card">
    <div class="auth-head">
      <img class="brand-mark brand-mark-lg" src="/img/logo.svg" width="64" height="64" alt="">
      <p class="page-eyebrow">$(HtmlEncode $global:Config.BarangayName)</p>
      <h1 class="auth-title">Sign in</h1>
      <p class="auth-sub">Access your dashboard to submit and track your reports.</p>
    </div>

    $(New-FlashHtml $Ctx)
    $(New-ErrorSummary $errors)

    <form method="post" action="/login" class="form-stack" novalidate>
      <input type="hidden" name="csrf_token" value="$(HtmlEncode $anonCsrf)">
      $nextInput

      <div class="field">
        <label for="email">Email address</label>
        <input type="email" id="email" name="email" inputmode="email" autocomplete="email"
               placeholder="you@example.com" required
               value="$(HtmlEncode $values['email'])"$(Get-FieldInvalidClass $errors 'email')>
        $(New-FieldErrorHtml $errors 'email')
      </div>

      <div class="field">
        <div class="field-head">
          <label for="password">Password</label>
          <a class="field-hint-link" href="/#faq">Forgot password?</a>
        </div>
        <div class="password-field">
          <input type="password" id="password" name="password" autocomplete="current-password"
                 placeholder="Your password" required$(Get-FieldInvalidClass $errors 'password')
                 data-password-input>
          <button type="button" class="password-toggle" data-password-toggle="password"
                  aria-label="Show password">Show</button>
        </div>
        $(New-FieldErrorHtml $errors 'password')
      </div>

      <button class="btn btn-primary btn-block" type="submit">Sign in</button>
    </form>

    <p class="auth-alt">New to the system? <a href="/register">Create a resident account</a></p>

    <div class="demo-box">
      <p class="demo-title">Demo accounts</p>
      <table class="demo-table">
        <thead><tr><th>Role</th><th>Email</th><th>Password</th></tr></thead>
        <tbody>
          <tr><td><span class="role-pill role-admin">Administrator</span></td><td><code>admin@barangay.gov.ph</code></td><td><code>Admin@12345</code></td></tr>
          <tr><td><span class="role-pill role-resident">Resident</span></td><td><code>resident@barangay.gov.ph</code></td><td><code>Resident@12345</code></td></tr>
        </tbody>
      </table>
      <p class="demo-hint">Use the <strong>Fill demo credentials</strong> button on the register page to autofill, or copy these here.</p>
    </div>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title 'Sign in' -BodyHtml $body -ActiveNav 'login')
}

function Test-SafeRedirect {
    param([string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return $false }
    if (-not $Target.StartsWith('/')) { return $false }
    if ($Target.StartsWith('//')) { return $false }     # protocol-relative
    if ($Target -match '[\r\n]') { return $false }
    return $true
}

function Invoke-DoLogin {
    param($Ctx)

    # Visitors who are not signed in have no session, so CSRF cannot be tied to
    # one. We instead require the login form to carry the same double-submit
    # cookie value, which blocks cross-site form posts.
    $cookieToken = Get-RequestCookie -Request $Ctx.Request -Name 'bcr_csrf'
    $formToken   = Get-FormValue -Body $Ctx.Body -Name 'csrf_token'
    if ([string]::IsNullOrWhiteSpace($cookieToken) -or $cookieToken -ne $formToken) {
        $Ctx.Flash = @{ type = 'error'; message = 'Your sign-in form expired. Please try again.' }
        Send-Redirect -Response $Ctx.Response -Location '/login'
        return
    }

    $result  = Validate-LoginInput -Body $Ctx.Body
    $values  = $result.Values
    $errors  = $result.Errors

    $next = [string]$values['next']
    if (-not (Test-SafeRedirect $next)) { $next = '' }

    $user = $null
    if ($errors.Count -eq 0) {
        $user = Get-UserByEmail ([string]$values['email'])
        if ($null -eq $user) {
            $errors['email'] = 'We could not find an account with that email address.'
        }
        elseif (-not (Test-PasswordAgainstRecord -Password ([string]$values['password']) -User $user)) {
            # Same message for "wrong password" and "no such account" style leaks
            $errors['password'] = 'The password you entered is incorrect. Please try again.'
        }
        elseif ($user.PSObject.Properties.Name -contains 'active' -and -not [bool]$user.active) {
            $errors['email'] = 'This account has been deactivated. Please contact the Barangay Hall.'
        }
    }

    if ($errors.Count -gt 0) {
        $Ctx.Errors   = $errors
        $Ctx.FormData = @{ email = $values['email']; next = $next }
        Invoke-ShowLogin -Ctx $Ctx
        return
    }

    # Rotate the session token on sign-in (prevents session fixation).
    $null = Start-UserSession -User $user -Response $Ctx.Response -Request $Ctx.Request
    Save-Database

    $destination = if (-not [string]::IsNullOrWhiteSpace($next)) { $next } else { '/dashboard' }
    Send-Redirect -Response $Ctx.Response -Location $destination
}

function Invoke-ShowRegister {
    param($Ctx)

    if ($null -ne $Ctx.Auth.User) {
        Send-Redirect -Response $Ctx.Response -Location '/dashboard'
        return
    }

    $errors = $Ctx.Errors
    $anonCsrf = Get-AnonymousCsrfToken -Ctx $Ctx
    $v = $Ctx.FormData

    $body = @"
<section class="auth-shell">
  <div class="auth-card auth-card-lg">
    <div class="auth-head">
      <img class="brand-mark brand-mark-lg" src="/img/logo.svg" width="64" height="64" alt="">
      <p class="page-eyebrow">Resident registration</p>
      <h1 class="auth-title">Create your account</h1>
      <p class="auth-sub">Register once and you can submit and follow up on every report you file with the barangay.</p>
    </div>

    $(New-FlashHtml $Ctx)
    $(New-ErrorSummary $errors)

    <form method="post" action="/register" class="form-stack" novalidate>
      <input type="hidden" name="csrf_token" value="$(HtmlEncode $anonCsrf)">
      <div class="field">
        <label for="name">Full name <span class="req" aria-hidden="true">*</span></label>
        <input type="text" id="name" name="name" autocomplete="name" maxlength="80"
               placeholder="Juan Dela Cruz" required$(Get-FieldInvalidClass $errors 'name')
               value="$(Get-RehydratedValue $v 'name')">
        $(New-FieldErrorHtml $errors 'name')
      </div>

      <div class="field">
        <label for="email">Email address <span class="req" aria-hidden="true">*</span></label>
        <input type="email" id="email" name="email" inputmode="email" autocomplete="email"
               maxlength="190" placeholder="you@example.com" required$(Get-FieldInvalidClass $errors 'email')
               value="$(Get-RehydratedValue $v 'email')">
        <p class="field-hint">Your email is your username. We only use it to send you report updates.</p>
        $(New-FieldErrorHtml $errors 'email')
      </div>

      <div class="field">
        <label for="phone">Mobile number <span class="optional">optional</span></label>
        <input type="tel" id="phone" name="phone" inputmode="tel" autocomplete="tel" maxlength="20"
               placeholder="0917 123 4567"$(Get-FieldInvalidClass $errors 'phone')
               value="$(Get-RehydratedValue $v 'phone')">
        $(New-FieldErrorHtml $errors 'phone')
      </div>

      <div class="field">
        <label for="address">Home address / purok <span class="optional">optional</span></label>
        <input type="text" id="address" name="address" autocomplete="street-address" maxlength="160"
               placeholder="Purok 5, San Isidro"$(Get-FieldInvalidClass $errors 'address')
               value="$(Get-RehydratedValue $v 'address')">
        $(New-FieldErrorHtml $errors 'address')
      </div>

      <div class="field">
        <label for="password">Password <span class="req" aria-hidden="true">*</span></label>
        <div class="password-field">
          <input type="password" id="password" name="password" autocomplete="new-password"
                 maxlength="128" placeholder="Create a strong password" required
                 data-password-input data-strength-input$(Get-FieldInvalidClass $errors 'password')>
          <button type="button" class="password-toggle" data-password-toggle="password"
                  aria-label="Show password">Show</button>
        </div>
        <div class="strength" data-strength-meter hidden>
          <div class="strength-bar"><span data-strength-fill></span></div>
          <p class="strength-label" data-strength-label>Strength: -</p>
        </div>
        <ul class="rule-list">
          <li data-rule="length">At least 8 characters</li>
          <li data-rule="letter">Contains a letter</li>
          <li data-rule="number">Contains a number</li>
          <li data-rule="symbol">Contains a special character</li>
        </ul>
        $(New-FieldErrorHtml $errors 'password')
      </div>

      <div class="field">
        <label for="passwordConfirm">Confirm password <span class="req" aria-hidden="true">*</span></label>
        <div class="password-field">
          <input type="password" id="passwordConfirm" name="passwordConfirm" autocomplete="new-password"
                 placeholder="Type your password again" required>
          <button type="button" class="password-toggle" data-password-toggle="passwordConfirm"
                  aria-label="Show password">Show</button>
        </div>
        <p class="field-error" data-match-error hidden>The two passwords do not match.</p>
      </div>

      <label class="checkbox">
        <input type="checkbox" name="agree" value="yes" required data-agree-input>
        <span>I confirm that the details I entered are correct, and I understand that
        reports I submit will be reviewed by authorized barangay personnel.</span>
      </label>

      <button class="btn btn-primary btn-block" type="submit">Create account</button>
      <button class="btn btn-ghost btn-block" type="button" data-fill-demo>Fill demo credentials</button>
    </form>

    <p class="auth-alt">Already registered? <a href="/login">Sign in instead</a></p>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title 'Create an account' -BodyHtml $body -ActiveNav 'register')
}

function Invoke-DoRegister {
    param($Ctx)

    $cookieToken = Get-RequestCookie -Request $Ctx.Request -Name 'bcr_csrf'
    $formToken   = Get-FormValue -Body $Ctx.Body -Name 'csrf_token'
    if ([string]::IsNullOrWhiteSpace($cookieToken) -or $cookieToken -ne $formToken) {
        $Ctx.Flash = @{ type = 'error'; message = 'Your registration form expired. Please try again.' }
        Send-Redirect -Response $Ctx.Response -Location '/register'
        return
    }

    $result = Validate-RegistrationInput -Body $Ctx.Body -Mode 'register'
    $values = $result.Values
    $errors = $result.Errors

    # --- password + confirmation -------------------------------------------
    # Every field is checked so the resident sees all problems at once rather
    # than fixing them one error message at a time.
    $policyError = Test-PasswordPolicy ([string]$values['password'])
    if ($null -ne $policyError) {
        $errors['password'] = $policyError
    }
    else {
        $confirm = Get-FormValue -Body $Ctx.Body -Name 'passwordConfirm'
        if ([string]::IsNullOrWhiteSpace($confirm)) {
            $errors['passwordConfirm'] = 'Please type your password again to confirm.'
        }
        elseif ($confirm -ne [string]$values['password']) {
            $errors['passwordConfirm'] = 'The two passwords do not match.'
        }
    }

    # --- required consent ---------------------------------------------------
    $agreed = Get-FormValue -Body $Ctx.Body -Name 'agree'
    if ($agreed -ne 'yes') {
        $errors['agree'] = 'Please tick the confirmation box before creating your account.'
    }

    if ($errors.Count -gt 0) {
        $Ctx.Errors   = $errors
        $Ctx.FormData = @{
            name    = $values['name']
            email   = $values['email']
            phone   = $values['phone']
            address = $values['address']
        }
        Invoke-ShowRegister -Ctx $Ctx
        return
    }

    $user = New-UserRecord -Name $values['name'] -Email $values['email'] `
        -Password $values['password'] -Role 'resident' `
        -Phone $values['phone'] -Address $values['address']

    $null = Start-UserSession -User $user -Response $Ctx.Response -Request $Ctx.Request
    Save-Database

    Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/dashboard' 'welcome' @{ name = $user.name })
}

function Invoke-DoLogout {
    param($Ctx)

    $user = $Ctx.Auth.User
    if ($null -ne $user) {
        # Logout is a POST with a session CSRF token, so validate it.
        if (-not (Test-CsrfToken -Ctx $Ctx)) {
            Send-Html -Response $Ctx.Response -StatusCode 400 -Html (New-HtmlDocument `
                -Title 'Invalid request' -User $user `
                -BodyHtml (New-ErrorBody -StatusCode 400 `
                    -Heading 'That request could not be verified' `
                    -Message 'Your sign-out request failed its security check. Please go back and try again.'))
            return
        }
        Add-ActivityLog -Action 'logout' -ActorId $user.id -Detail 'Signed out'
    }

    $wasSignedIn = ($null -ne $Ctx.Auth.User)
    End-UserSession -Ctx $Ctx -Response $Ctx.Response
    Save-Database
    if ($wasSignedIn) {
        Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/' 'loggedout' @{})
    } else {
        Send-Redirect -Response $Ctx.Response -Location '/'
    }
}

function Invoke-Profile {
    param($Ctx)

    $user  = $Ctx.Auth.User
    $csrf  = Get-CsrfToken -Ctx $Ctx
    $errors = $Ctx.Errors
    $v = $Ctx.FormData

    $name    = if ($null -ne $v -and $v.ContainsKey('name')) { [string]$v['name'] } else { [string]$user.name }
    $email   = if ($null -ne $v -and $v.ContainsKey('email')) { [string]$v['email'] } else { [string]$user.email }
    $phone   = if ($null -ne $v -and $v.ContainsKey('phone')) { [string]$v['phone'] } else { [string]$user.phone }
    $address = if ($null -ne $v -and $v.ContainsKey('address')) { [string]$v['address'] } else { [string]$user.address }

    $roleLabel = if (Test-IsAdmin $user) { 'Administrator' } else { 'Resident' }
    $roleTone  = if (Test-IsAdmin $user) { 'role-admin' } else { 'role-resident' }
    $joined    = (Get-DateTimeFromIso ([string]$user.createdAt)).ToString('dd MMMM yyyy')
    $lastLogin = '-'
    $ll = Get-DateTimeFromIso ([string]$user.lastLoginAt)
    if ($ll -ne [DateTime]::MinValue) { $lastLogin = $ll.ToString('dd MMM yyyy, hh:mm tt') }
    $stats = Get-ComplaintStats -UserId $user.id

    $body = @"
<section class="container section">
  $(New-PageIntro -Eyebrow 'My account' -Heading 'Profile and security' -Sub 'Keep your contact details current so the barangay can reach you about your reports.')

  $(New-FlashHtml $Ctx)
  $(New-ErrorSummary $errors)

  <div class="split-grid">
    <div class="card">
      <div class="card-head">
        <h2 class="card-title">Personal information</h2>
        <span class="role-pill $roleTone">$roleLabel</span>
      </div>
      <form method="post" action="/profile" class="form-stack" novalidate>
        <input type="hidden" name="csrf_token" value="$(HtmlEncode $csrf)">

        <div class="field">
          <label for="name">Full name</label>
          <input type="text" id="name" name="name" maxlength="80" required
                 value="$(HtmlEncode $name)"$(Get-FieldInvalidClass $errors 'name')>
          $(New-FieldErrorHtml $errors 'name')
        </div>

        <div class="field">
          <label for="email">Email address</label>
          <input type="email" id="email" name="email" maxlength="190" required
                 value="$(HtmlEncode $email)"$(Get-FieldInvalidClass $errors 'email')>
          $(New-FieldErrorHtml $errors 'email')
        </div>

        <div class="field">
          <label for="phone">Mobile number <span class="optional">optional</span></label>
          <input type="tel" id="phone" name="phone" maxlength="20" value="$(HtmlEncode $phone)">
        </div>

        <div class="field">
          <label for="address">Home address / purok <span class="optional">optional</span></label>
          <input type="text" id="address" name="address" maxlength="160" value="$(HtmlEncode $address)">
        </div>

        <div class="form-actions">
          <button class="btn btn-primary" type="submit">Save changes</button>
          <a class="btn btn-ghost" href="/dashboard">Cancel</a>
        </div>
      </form>
    </div>

    <div class="side-stack">
      <div class="card card-flush">
        <div class="card-head"><h2 class="card-title">Account summary</h2></div>
        <dl class="detail-list">
          <div><dt>Account type</dt><dd><span class="role-pill $roleTone">$roleLabel</span></dd></div>
          <div><dt>Member since</dt><dd>$(HtmlEncode $joined)</dd></div>
          <div><dt>Last sign-in</dt><dd>$(HtmlEncode $lastLogin)</dd></div>
          <div><dt>Reports filed</dt><dd>$($stats.Total)</dd></div>
          <div><dt>Resolved</dt><dd>$($stats.Resolved)</dd></div>
        </dl>
      </div>

      <div class="card">
        <div class="card-head"><h2 class="card-title">Password</h2></div>
        <p class="card-text">Your password is stored as a salted PBKDF2 hash. Plain text is never written to disk.</p>
        <a class="btn btn-outline btn-block" href="/profile/password">Change password</a>
      </div>

      <div class="card">
        <div class="card-head"><h2 class="card-title">Need to sign out?</h2></div>
        <form method="post" action="/logout" class="inline-form">
          <input type="hidden" name="csrf_token" value="$(HtmlEncode $csrf)">
          <button class="btn btn-danger-ghost btn-block" type="submit">Sign out of this device</button>
        </form>
      </div>
    </div>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title 'My profile' -BodyHtml $body -ActiveNav 'profile' -User $user -CsrfToken $csrf)
}

function Invoke-UpdateProfile {
    param($Ctx)

    $user = $Ctx.Auth.User
    if (-not (Test-CsrfToken -Ctx $Ctx)) {
        Send-Html -Response $Ctx.Response -StatusCode 400 -Html (New-HtmlDocument `
            -Title 'Invalid request' -User $user -CsrfToken (Get-CsrfToken $Ctx) `
            -BodyHtml (New-ErrorBody -StatusCode 400 -Heading 'That request could not be verified' `
                -Message 'Your form failed its security check. Please go back and try again.'))
        return
    }

    $body = @{} + $Ctx.Body
    $body['userId'] = $user.id
    $result = Validate-RegistrationInput -Body $body -Mode 'profile'
    $values = $result.Values
    $errors = $result.Errors

    if ($errors.Count -gt 0) {
        $Ctx.Errors   = $errors
        $Ctx.FormData = @{
            name    = $values['name']
            email   = $values['email']
            phone   = $values['phone']
            address = $values['address']
        }
        Invoke-Profile -Ctx $Ctx
        return
    }

    $user | Add-Member -NotePropertyName 'name'      -NotePropertyValue $values['name']  -Force
    $user | Add-Member -NotePropertyName 'email'     -NotePropertyValue ($values['email'].ToLowerInvariant()) -Force
    $user | Add-Member -NotePropertyName 'phone'     -NotePropertyValue $values['phone'] -Force
    $user | Add-Member -NotePropertyName 'address'   -NotePropertyValue $values['address'] -Force
    $user | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue (Get-NowIso) -Force
    $null = Save-User $user

    Write-AuditLog -Ctx $Ctx -Action 'profile_update' -Detail 'Updated own profile details'
    $Ctx.Flash = @{ type = 'success'; message = 'Your profile has been updated.' }
    Invoke-Profile -Ctx $Ctx
}

function Invoke-ChangePasswordForm {
    param($Ctx)

    $user  = $Ctx.Auth.User
    $csrf  = Get-CsrfToken -Ctx $Ctx
    $errors = $Ctx.Errors

    $body = @"
<section class="container section-narrow">
  $(New-PageIntro -Eyebrow 'Security' -Heading 'Change your password' -Sub 'You will stay signed in on this device after changing your password.')

  $(New-FlashHtml $Ctx)
  $(New-ErrorSummary $errors)

  <div class="card">
    <form method="post" action="/profile/password" class="form-stack" novalidate>
      <input type="hidden" name="csrf_token" value="$(HtmlEncode $csrf)">

      <div class="field">
        <label for="currentPassword">Current password</label>
        <div class="password-field">
          <input type="password" id="currentPassword" name="currentPassword"
                 autocomplete="current-password" required$(Get-FieldInvalidClass $errors 'currentPassword')
                 data-password-input>
          <button type="button" class="password-toggle" data-password-toggle="currentPassword"
                  aria-label="Show password">Show</button>
        </div>
        $(New-FieldErrorHtml $errors 'currentPassword')
      </div>

      <div class="field">
        <label for="newPassword">New password</label>
        <div class="password-field">
          <input type="password" id="newPassword" name="newPassword" autocomplete="new-password"
                 maxlength="128" required data-password-input data-strength-input
                 $(Get-FieldInvalidClass $errors 'newPassword')>
          <button type="button" class="password-toggle" data-password-toggle="newPassword"
                  aria-label="Show password">Show</button>
        </div>
        <div class="strength" data-strength-meter hidden>
          <div class="strength-bar"><span data-strength-fill></span></div>
          <p class="strength-label" data-strength-label>Strength: -</p>
        </div>
        <ul class="rule-list">
          <li data-rule="length">At least 8 characters</li>
          <li data-rule="letter">Contains a letter</li>
          <li data-rule="number">Contains a number</li>
          <li data-rule="symbol">Contains a special character</li>
        </ul>
        $(New-FieldErrorHtml $errors 'newPassword')
      </div>

      <div class="field">
        <label for="confirmPassword">Confirm new password</label>
        <div class="password-field">
          <input type="password" id="confirmPassword" name="confirmPassword"
                 autocomplete="new-password" required>
          <button type="button" class="password-toggle" data-password-toggle="confirmPassword"
                  aria-label="Show password">Show</button>
        </div>
        <p class="field-error" data-match-error hidden>The two passwords do not match.</p>
      </div>

      <div class="form-actions">
        <button class="btn btn-primary" type="submit">Update password</button>
        <a class="btn btn-ghost" href="/profile">Cancel</a>
      </div>
    </form>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title 'Change password' -BodyHtml $body -ActiveNav 'profile' -User $user -CsrfToken $csrf)
}

function Invoke-ChangePassword {
    param($Ctx)

    $user = $Ctx.Auth.User
    $csrf = Get-CsrfToken -Ctx $Ctx
    if (-not (Test-CsrfToken -Ctx $Ctx)) {
        Send-Html -Response $Ctx.Response -StatusCode 400 -Html (New-HtmlDocument `
            -Title 'Invalid request' -User $user -CsrfToken $csrf `
            -BodyHtml (New-ErrorBody -StatusCode 400 -Heading 'That request could not be verified' `
                -Message 'Your form failed its security check. Please go back and try again.'))
        return
    }

    $errors = @{}
    $current = [string]$(if ($Ctx.Body.ContainsKey('currentPassword')) { $Ctx.Body['currentPassword'] } else { '' })
    $new     = [string]$(if ($Ctx.Body.ContainsKey('newPassword'))     { $Ctx.Body['newPassword'] }     else { '' })
    $confirm = [string]$(if ($Ctx.Body.ContainsKey('confirmPassword')) { $Ctx.Body['confirmPassword'] } else { '' })

    if ([string]::IsNullOrWhiteSpace($current)) {
        $errors['currentPassword'] = 'Please enter your current password.'
    }
    elseif (-not (Test-PasswordAgainstRecord -Password $current -User $user)) {
        $errors['currentPassword'] = 'Your current password is incorrect.'
    }

    $policyError = Test-PasswordPolicy $new
    if ($null -ne $policyError) {
        $errors['newPassword'] = $policyError
    }
    elseif ($new -eq $current) {
        $errors['newPassword'] = 'Your new password must be different from your current password.'
    }

    if ([string]::IsNullOrWhiteSpace($confirm)) {
        $errors['confirmPassword'] = 'Please type your new password again.'
    }
    elseif ($new -ne $confirm) {
        $errors['confirmPassword'] = 'The two passwords do not match.'
    }

    if ($errors.Count -gt 0) {
        $Ctx.Errors = $errors
        Invoke-ChangePasswordForm -Ctx $Ctx
        return
    }

    $null = Set-UserPassword -User $user -Password $new
    Remove-AllSessionsForUser -UserId $user.id
    $session = Start-UserSession -User $user -Response $Ctx.Response -Request $Ctx.Request
    Save-Database

    Write-AuditLog -Ctx $Ctx -Action 'password_change' -Detail 'Changed own password; other sessions revoked'
    $Ctx.Flash = @{ type = 'success'; message = 'Your password has been changed. Other devices have been signed out.' }
    Invoke-Profile -Ctx $Ctx
}
