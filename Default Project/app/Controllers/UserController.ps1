# ============================================================================
#  Controllers/UserController.ps1
#  Second level of access: administrator-only account management
# ============================================================================

function Invoke-UserList {
    param($Ctx)

    $admin = $Ctx.Auth.User
    $csrf  = Get-CsrfToken -Ctx $Ctx

    $search = Get-QueryValue -Request $Ctx.Request -Name 'q'
    $role   = Get-QueryValue -Request $Ctx.Request -Name 'role'
    $state  = Get-QueryValue -Request $Ctx.Request -Name 'state'
    if ($role  -and ($role  -notin @('admin', 'resident')))  { $role = '' }
    if ($state -and ($state -notin @('active', 'inactive'))) { $state = '' }

    $users = @(Get-AllUsers)
    if ($search) {
        $needle = $search.ToLowerInvariant()
        $users = @($users | Where-Object {
            ([string]$_.name).ToLowerInvariant().Contains($needle) -or
            ([string]$_.email).ToLowerInvariant().Contains($needle) -or
            ([string]$_.address).ToLowerInvariant().Contains($needle)
        })
    }
    if ($role)  { $users = @($users | Where-Object { $_.role -eq $role }) }
    if ($state) {
        if ($state -eq 'active')   { $users = @($users | Where-Object { [bool]$_.active }) }
        else                       { $users = @($users | Where-Object { -not [bool]$_.active }) }
    }

    $users = @($users | Sort-Object -Property createdAt -Descending)

    $allUsers  = @(Get-AllUsers)
    $statAll   = $allUsers.Count
    $statAdmins= @($allUsers | Where-Object { $_.role -eq 'admin' }).Count
    $statActive= @($allUsers | Where-Object { [bool]$_.active }).Count
    $statOff   = $statAll - $statActive

    $rowsHtml = ''
    foreach ($u in $users) {
        $rowsHtml += New-UserRowHtml -User $u -Admin $admin -Csrf $csrf
    }
    if ($users.Count -eq 0) {
        $rowsHtml = New-EmptyState -Icon '&#128101;' -Title 'No accounts match' `
            -Message 'Try a different search term or clear the filters.' `
            -Action '<a class="btn btn-outline" href="/users">Clear filters</a>'
    }

    $clearLink = ''
    if ($search -or $role -or $state) {
        $clearLink = '<a class="btn btn-ghost btn-sm" href="/users">Clear filters</a>'
    }

    $body = @"
<section class="container section">
  $(New-PageIntro -Eyebrow 'Administrator tools' -Heading 'Resident accounts' `
        -Sub 'Create accounts, promote residents to administrator, deactivate access and reset passwords.' `
        -Actions ('<a class="btn btn-primary" href="/users/new">+ Add resident</a>' + $clearLink))

  $(New-FlashHtml $Ctx)

  <div class="stat-grid stat-grid-4">
    $(New-StatTile -Label 'Total accounts' -Value $statAll    -Tone 'brand'  -Hint 'Residents and admins')
    $(New-StatTile -Label 'Administrators' -Value $statAdmins -Tone 'info'   -Hint 'Full management access')
    $(New-StatTile -Label 'Active'         -Value $statActive -Tone 'success' -Hint 'Can sign in')
    $(New-StatTile -Label 'Deactivated'    -Value $statOff    -Tone 'warning' -Hint 'Access blocked')
  </div>

  <form class="filter-bar" method="get" action="/users" data-auto-submit>
    <div class="field field-inline">
      <label for="q">Search</label>
      <input type="search" id="q" name="q" placeholder="Name, email or address&hellip;" value="$(HtmlEncode $search)">
    </div>
    <div class="field field-inline">
      <label for="role">Role</label>
      <select id="role" name="role">
        <option value="">All roles</option>
        <option value="resident"$(if ($role -eq 'resident') { ' selected' })>Resident</option>
        <option value="admin"$(if ($role -eq 'admin') { ' selected' })>Administrator</option>
      </select>
    </div>
    <div class="field field-inline">
      <label for="state">Status</label>
      <select id="state" name="state">
        <option value="">Any status</option>
        <option value="active"$(if ($state -eq 'active') { ' selected' })>Active</option>
        <option value="inactive"$(if ($state -eq 'inactive') { ' selected' })>Deactivated</option>
      </select>
    </div>
    <div class="filter-actions">
      <button class="btn btn-primary btn-sm" type="submit">Apply</button>
      <a class="btn btn-ghost btn-sm" href="/users">Reset</a>
    </div>
  </form>

  <p class="result-count">Showing <strong>$($users.Count)</strong> of <strong>$($allUsers.Count)</strong> account(s).</p>

  <div class="table-wrap">
    <table class="table">
      <thead>
        <tr>
          <th scope="col">Name</th>
          <th scope="col">Role</th>
          <th scope="col">Contact</th>
          <th scope="col">Reports</th>
          <th scope="col">Status</th>
          <th scope="col" class="col-actions">Actions</th>
        </tr>
      </thead>
      <tbody>
        $rowsHtml
      </tbody>
    </table>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title 'Resident accounts' -BodyHtml $body -ActiveNav 'users' -User $admin -CsrfToken $csrf)
}

function New-UserRowHtml {
    param($User, $Admin, [string]$Csrf)

    $isSelf     = ([string]$User.id -eq [string]$Admin.id)
    $isActive   = [bool]$User.active
    $isAdminRow = ([string]$User.role -eq 'admin')
    $name       = HtmlEncode ([string]$User.name)
    $email      = HtmlEncode ([string]$User.email)
    $phone      = HtmlEncode ([string]$User.phone)
    $address    = HtmlEncode ([string]$User.address)
    $idEncoded  = [System.Net.WebUtility]::UrlEncode([string]$User.id)
    $stats      = Get-ComplaintStats -UserId ([string]$User.id)

    $roleTone  = if ($isAdminRow) { 'role-admin' } else { 'role-resident' }
    $roleLabel = if ($isAdminRow) { 'Administrator' } else { 'Resident' }
    $statusHtml = if ($isActive) { '<span class="badge badge-success">Active</span>' }
                  else { '<span class="badge badge-muted">Deactivated</span>' }

    $contact = $email
    if (-not [string]::IsNullOrWhiteSpace($phone)) { $contact += '<br><span class="table-sub">' + $phone + '</span>' }
    if (-not [string]::IsNullOrWhiteSpace($address)) { $contact += '<br><span class="table-sub">' + $address + '</span>' }

    # --- promote / demote ---------------------------------------------------
    if ($isSelf) {
        $roleAction = '<span class="action-note">You are signed in as this account</span>'
    }
    elseif ($isAdminRow) {
        $roleAction = @"
<form method="post" action="/users/$idEncoded/role" class="inline-form">
  <input type="hidden" name="csrf_token" value="$Csrf">
  <input type="hidden" name="role" value="resident">
  <button class="btn btn-ghost btn-xs" type="submit" data-confirm="Demote this administrator to a regular resident?">Demote</button>
</form>
"@
    }
    else {
        $roleAction = @"
<form method="post" action="/users/$idEncoded/role" class="inline-form">
  <input type="hidden" name="csrf_token" value="$Csrf">
  <input type="hidden" name="role" value="admin">
  <button class="btn btn-outline btn-xs" type="submit" data-confirm="Promote this resident to administrator? They will gain full access to all reports and accounts.">Promote</button>
</form>
"@
    }

    # --- activate / deactivate ---------------------------------------------
    if ($isSelf) {
        $activeAction = '<span class="action-note">&mdash;</span>'
    }
    elseif ($isActive) {
        $activeAction = @"
<form method="post" action="/users/$idEncoded/toggle" class="inline-form">
  <input type="hidden" name="csrf_token" value="$Csrf">
  <button class="btn btn-ghost btn-xs" type="submit" data-confirm="Deactivate this account? The resident will not be able to sign in.">Deactivate</button>
</form>
"@
    }
    else {
        $activeAction = @"
<form method="post" action="/users/$idEncoded/toggle" class="inline-form">
  <input type="hidden" name="csrf_token" value="$Csrf">
  <button class="btn btn-outline btn-xs" type="submit">Reactivate</button>
</form>
"@
    }

    # --- delete -------------------------------------------------------------
    if ($isSelf) {
        $deleteAction = '<span class="action-note">&mdash;</span>'
    }
    else {
        $deleteAction = @"
<a class="btn btn-danger-ghost btn-xs" href="/users/$idEncoded/delete?confirm=0">Delete</a>
"@
    }

    $rowClass = if ($isActive) { '' } else { ' is-inactive' }

    return @"
<tr class="$rowClass" data-user-row>
  <th scope="row" data-label="Name">
    <div class="cell-user">
      $(Get-InitialsBadges $User)
      <span class="cell-user-text">$name</span>
    </div>
  </th>
  <td data-label="Role"><span class="role-pill $roleTone">$roleLabel</span></td>
  <td data-label="Contact" class="table-contact">$contact</td>
  <td data-label="Reports">$($stats.Total)</td>
  <td data-label="Status">$statusHtml</td>
  <td data-label="Actions" class="col-actions">
    <div class="row-actions">$roleAction $activeAction $deleteAction</div>
  </td>
</tr>
"@
}

# ------------------------------------------------------- create a resident --
function Invoke-UserCreateForm {
    param($Ctx)

    $admin  = $Ctx.Auth.User
    $csrf   = Get-CsrfToken -Ctx $Ctx
    $errors = $Ctx.Errors
    $v      = $Ctx.FormData
    $role   = [string]$(if ([string]$v['role'] -eq 'admin') { 'admin' } else { 'resident' })

    $body = @"
<section class="container section-narrow">
  <nav class="breadcrumb" aria-label="Breadcrumb">
    <a href="/users">&larr; Back to accounts</a>
  </nav>

  $(New-PageIntro -Eyebrow 'Administrator tools' -Heading 'Add a resident account' `
        -Sub 'Create an account on behalf of a resident who cannot register online yet. You can change the role later.')

  $(New-FlashHtml $Ctx)
  $(New-ErrorSummary $errors)

  <div class="card">
    <form method="post" action="/users/new" class="form-stack" novalidate>
      <input type="hidden" name="csrf_token" value="$(HtmlEncode $csrf)">

      <div class="field">
        <label for="name">Full name <span class="req" aria-hidden="true">*</span></label>
        <input type="text" id="name" name="name" maxlength="80" required
               placeholder="Maria Santos" value="$(Get-RehydratedValue $v 'name')"$(Get-FieldInvalidClass $errors 'name')>
        $(New-FieldErrorHtml $errors 'name')
      </div>

      <div class="field">
        <label for="email">Email address <span class="req" aria-hidden="true">*</span></label>
        <input type="email" id="email" name="email" maxlength="190" required
               placeholder="maria@example.com" value="$(Get-RehydratedValue $v 'email')"$(Get-FieldInvalidClass $errors 'email')>
        $(New-FieldErrorHtml $errors 'email')
      </div>

      <div class="field-grid">
        <div class="field">
          <label for="phone">Mobile number <span class="optional">optional</span></label>
          <input type="tel" id="phone" name="phone" maxlength="20"
                 placeholder="0917 123 4567" value="$(Get-RehydratedValue $v 'phone')">
          $(New-FieldErrorHtml $errors 'phone')
        </div>
        <div class="field">
          <label for="role">Access level <span class="req" aria-hidden="true">*</span></label>
          <select id="role" name="role" required>
            <option value="resident"$(if ($role -eq 'resident') { ' selected' })>Resident - own reports only</option>
            <option value="admin"$(if ($role -eq 'admin') { ' selected' })>Administrator - full access</option>
          </select>
        </div>
      </div>

      <div class="field">
        <label for="address">Home address / purok <span class="optional">optional</span></label>
        <input type="text" id="address" name="address" maxlength="160"
               placeholder="Purok 2, San Isidro" value="$(Get-RehydratedValue $v 'address')">
      </div>

      <div class="field">
        <label for="password">Temporary password <span class="req" aria-hidden="true">*</span></label>
        <div class="password-field">
          <input type="password" id="password" name="password" maxlength="128" required
                 autocomplete="new-password" data-password-input data-strength-input
                 $(Get-FieldInvalidClass $errors 'password')>
          <button type="button" class="password-toggle" data-password-toggle="password" aria-label="Show password">Show</button>
        </div>
        <div class="strength" data-strength-meter hidden>
          <div class="strength-bar"><span data-strength-fill></span></div>
          <p class="strength-label" data-strength-label>Strength: -</p>
        </div>
        <p class="field-hint">Share this with the resident and ask them to change it after their first sign-in.</p>
        $(New-FieldErrorHtml $errors 'password')
      </div>

      <div class="field">
        <label for="passwordConfirm">Confirm password <span class="req" aria-hidden="true">*</span></label>
        <div class="password-field">
          <input type="password" id="passwordConfirm" name="passwordConfirm" maxlength="128" required
                 autocomplete="new-password">
          <button type="button" class="password-toggle" data-password-toggle="passwordConfirm" aria-label="Show password">Show</button>
        </div>
        <p class="field-error" data-match-error hidden>The two passwords do not match.</p>
      </div>

      <div class="form-actions">
        <button class="btn btn-primary" type="submit">Create account</button>
        <a class="btn btn-ghost" href="/users">Cancel</a>
      </div>
    </form>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title 'Add a resident account' -BodyHtml $body -ActiveNav 'users' -User $admin -CsrfToken $csrf)
}

function Invoke-UserCreate {
    param($Ctx)

    $admin = $Ctx.Auth.User
    if (-not (Test-CsrfToken -Ctx $Ctx)) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 400 -Heading 'That request could not be verified' `
            -Message 'Your form failed its security check. Please go back and try again.' -User $admin
        return
    }

    $result = Validate-RegistrationInput -Body $Ctx.Body -Mode 'register'
    $values = $result.Values
    $errors = $result.Errors

    $role = Get-FormValue -Body $Ctx.Body -Name 'role'
    if ($role -notin @('admin', 'resident')) { $role = 'resident' }

    $policyError = Test-PasswordPolicy ([string]$values['password'])
    if ($null -ne $policyError) { $errors['password'] = $policyError }
    else {
        $confirm = Get-FormValue -Body $Ctx.Body -Name 'passwordConfirm'
        if ([string]::IsNullOrWhiteSpace($confirm)) { $errors['passwordConfirm'] = 'Please type the password again to confirm.' }
        elseif ($confirm -ne [string]$values['password']) { $errors['passwordConfirm'] = 'The two passwords do not match.' }
    }

    if ($errors.Count -gt 0) {
        $Ctx.Errors   = $errors
        $Ctx.FormData = @{
            name    = $values['name']
            email   = $values['email']
            phone   = $values['phone']
            address = $values['address']
            role    = $role
        }
        Invoke-UserCreateForm -Ctx $Ctx
        return
    }

    $user = New-UserRecord -Name $values['name'] -Email $values['email'] -Password $values['password'] `
        -Role $role -Phone $values['phone'] -Address $values['address']

    Write-AuditLog -Ctx $Ctx -Action 'user_create' -Detail ('Created ' + $role + ' account for ' + $user.email)

    Send-Redirect -Response $Ctx.Response -Location `
        (Get-FlashUrl '/users' 'usercreated' @{ name = $user.name; email = $user.email })
}

# -------------------------------------------------- delete confirmation page --
function Invoke-UserDeleteConfirm {
    param($Ctx, [string]$Id)

    $admin = $Ctx.Auth.User
    $csrf  = Get-CsrfToken -Ctx $Ctx
    $user  = Get-UserById $Id

    if ($null -eq $user) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 404 -Heading 'Account not found' `
            -Message 'This account does not exist, or it has already been deleted.' -User $admin
        return
    }
    if ([string]$user.id -eq [string]$admin.id) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 403 -Heading 'You cannot delete your own account' `
            -Message 'Ask another administrator to remove this account for you.' -User $admin
        return
    }

    $stats = Get-ComplaintStats -UserId ([string]$user.id)
    $idEncoded = [System.Net.WebUtility]::UrlEncode([string]$user.id)

    $warning = ''
    if ($stats.Total -gt 0) {
        $warning = @"
<div class="alert alert-warning">
  <span class="alert-icon" aria-hidden="true">&#9888;</span>
  <div><strong>This account owns $($stats.Total) report(s).</strong>
  <ul class="alert-list">
    <li>$($stats.Pending) pending, $($stats.InReview) in review, $($stats.Resolved) resolved</li>
  </ul>
  Those reports will also be permanently removed from the barangay records.</div>
</div>
"@
    }

    $roleLabel = if ([string]$user.role -eq 'admin') { 'Administrator' } else { 'Resident' }

    $body = @"
<section class="container section-narrow">
  <nav class="breadcrumb" aria-label="Breadcrumb">
    <a href="/users">&larr; Back to accounts</a>
  </nav>

  $(New-PageIntro -Eyebrow 'Confirm deletion' -Heading 'Delete this account?' -Sub 'The account will be removed permanently and will no longer be able to sign in.')

  $(New-FlashHtml $Ctx)

  <div class="card card-danger">
    <div class="danger-head">
      <span class="danger-icon" aria-hidden="true">&#128465;</span>
      <div>
        <h2 class="danger-title">This action cannot be undone</h2>
        <p class="danger-text">Please review the account details below before you continue.</p>
      </div>
    </div>

    $warning

    <dl class="detail-list">
      <div><dt>Full name</dt><dd>$(HtmlEncode ([string]$user.name))</dd></div>
      <div><dt>Email address</dt><dd>$(HtmlEncode ([string]$user.email))</dd></div>
      <div><dt>Access level</dt><dd>$(HtmlEncode $roleLabel)</dd></div>
      <div><dt>Registered on</dt><dd>$(HtmlEncode ((Get-DateTimeFromIso ([string]$user.createdAt)).ToString('dd MMMM yyyy')))</dd></div>
      <div><dt>Reports owned</dt><dd>$($stats.Total)</dd></div>
    </dl>

    <div class="form-actions form-actions-split">
      <form method="post" action="/users/$idEncoded/delete" class="inline-form">
        <input type="hidden" name="csrf_token" value="$(HtmlEncode $csrf)">
        <input type="hidden" name="confirm" value="yes">
        <button class="btn btn-danger" type="submit">Yes, delete this account</button>
      </form>
      <a class="btn btn-ghost" href="/users">Cancel, keep the account</a>
    </div>
  </div>
</section>
"@

    Send-Html -Response $Ctx.Response -Html (New-HtmlDocument -Title 'Confirm account deletion' -BodyHtml $body -ActiveNav 'users' -User $admin -CsrfToken $csrf)
}

# ------------------------------------------------------- admin user actions --
function Invoke-UserAction {
    param($Ctx, [string]$Id, [string]$Verb)

    $admin = $Ctx.Auth.User

    if (-not (Test-CsrfToken -Ctx $Ctx)) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 400 -Heading 'That request could not be verified' `
            -Message 'Your form failed its security check. Please go back and try again.' -User $admin
        return
    }

    $user = Get-UserById $Id
    if ($null -eq $user) {
        Send-ErrorPage -Response $Ctx.Response -StatusCode 404 -Heading 'Account not found' `
            -Message 'This account does not exist, or it has already been deleted.' -User $admin
        return
    }

    if ([string]$user.id -eq [string]$admin.id) {
        Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/users' 'selfchange' @{})
        return
    }

    switch ($Verb) {

        'toggle' {
            $newActive = -not [bool]$user.active
            $user | Add-Member -NotePropertyName 'active'   -NotePropertyValue $newActive -Force
            $user | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue (Get-NowIso)   -Force
            $null = Save-User $user

            if (-not $newActive) {
                # Kick any live sessions immediately.
                Remove-AllSessionsForUser -UserId $user.id
            }
            Write-AuditLog -Ctx $Ctx -Action 'user_toggle' `
                -Detail (($user.email) + ' -> ' + $(if ($newActive) { 'active' } else { 'deactivated' }))
            if ($newActive) {
                Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/users' 'useractive' @{ name = $user.name })
            } else {
                Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/users' 'userinactive' @{ name = $user.name })
            }
        }

        'role' {
            $newRole = Get-FormValue -Body $Ctx.Body -Name 'role'
            if ($newRole -notin @('admin', 'resident')) {
                Send-ErrorPage -Response $Ctx.Response -StatusCode 400 -Heading 'Invalid access level' `
                    -Message 'Please choose either Resident or Administrator.' -User $admin
                return
            }

            $activeAdmins = @(@(Get-AllUsers) | Where-Object { $_.role -eq 'admin' -and [bool]$_.active }).Count
            if ([string]$user.role -eq 'admin' -and $newRole -eq 'resident' -and $activeAdmins -le 1) {
                Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/users' 'lastadmin' @{})
                return
            }

            $user | Add-Member -NotePropertyName 'role'      -NotePropertyValue $newRole -Force
            $user | Add-Member -NotePropertyName 'updatedAt' -NotePropertyValue (Get-NowIso) -Force
            $null = Save-User $user

            if ($newRole -ne 'admin') {
                # A demoted user must start a fresh session with the new role.
                Remove-AllSessionsForUser -UserId $user.id
            }

            Write-AuditLog -Ctx $Ctx -Action 'user_role' -Detail ($user.email + ' -> ' + $newRole)
            if ($newRole -eq 'admin') {
                Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/users' 'userrole' @{ name = $user.name; role = 'an administrator' })
            } else {
                Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/users' 'userrole' @{ name = $user.name; role = 'a resident' })
            }
        }

        'reset-password' {
            $newPassword = [string]$(if ($Ctx.Body.ContainsKey('newPassword')) { $Ctx.Body['newPassword'] } else { '' })
            $policyError = Test-PasswordPolicy $newPassword
            if ($null -ne $policyError) {
                Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/users' 'weakpassword' @{})
                return
            }
            $null = Set-UserPassword -User $user -Password $newPassword
            Remove-AllSessionsForUser -UserId $user.id
            Write-AuditLog -Ctx $Ctx -Action 'user_password_reset' -Detail ('Reset password for ' + $user.email)
            Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/users' 'pwreset' @{ name = $user.name })
        }

        'delete' {
            $confirm = Get-FormValue -Body $Ctx.Body -Name 'confirm'
            if ($confirm -ne 'yes') {
                Send-Redirect -Response $Ctx.Response -Location ('/users/' + [System.Net.WebUtility]::UrlEncode([string]$user.id) + '/delete')
                return
            }

            $activeAdmins = @(@(Get-AllUsers) | Where-Object { $_.role -eq 'admin' -and [bool]$_.active }).Count
            if ([string]$user.role -eq 'admin' -and $activeAdmins -le 1) {
                Send-Redirect -Response $Ctx.Response -Location (Get-FlashUrl '/users' 'lastadmin' @{})
                return
            }

            $email   = [string]$user.email
            $name    = [string]$user.name
            $owned   = @(Get-AllComplaints | Where-Object { [string]$_.reporterId -eq [string]$user.id })

            Remove-AllSessionsForUser -UserId $user.id
            Remove-UserRecord -Id $user.id
            foreach ($c in $owned) { Remove-ComplaintRecord -Id $c.id }
            Save-Database

            Write-AuditLog -Ctx $Ctx -Action 'user_delete' `
                -Detail ('Deleted ' + $email + ' and ' + $owned.Count + ' report(s)')
            Send-Redirect -Response $Ctx.Response -Location `
                (Get-FlashUrl '/users' 'userdeleted' @{ name = $name; count = $owned.Count })
        }

        default {
            Send-ErrorPage -Response $Ctx.Response -StatusCode 404 -Heading 'Unknown action' `
                -Message 'That account action is not supported.' -User $admin
        }
    }
}
