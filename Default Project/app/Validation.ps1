# ============================================================================
#  Validation.ps1 - friendly, field-level input validation
# ============================================================================

function Test-EmailAddress {
    param([string]$Email)
    if ([string]::IsNullOrWhiteSpace($Email)) { return $false }
    if ($Email.Length -gt 190) { return $false }
    if ($Email -notmatch '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$') { return $false }
    return $true
}

function Test-PhoneNumber {
    param([string]$Phone)
    if ([string]::IsNullOrWhiteSpace($Phone)) { return $true }   # optional field
    $digits = ($Phone -replace '[^0-9]')
    if ($digits.Length -lt 7 -or $digits.Length -gt 15) { return $false }
    return $true
}

function Test-PasswordPolicy {
    <#
        Minimum 8 characters, at least one letter and one number.
        Returns an error message, or $null when the password is acceptable.
    #>
    param([string]$Password)

    if ([string]::IsNullOrEmpty($Password)) {
        return 'Please choose a password.'
    }
    if ($Password.Length -lt 8) {
        return 'Your password must be at least 8 characters long.'
    }
    if ($Password.Length -gt 128) {
        return 'Your password is too long (maximum 128 characters).'
    }
    if ($Password -notmatch '[A-Za-z]') {
        return 'Your password must contain at least one letter.'
    }
    if ($Password -notmatch '[0-9]') {
        return 'Your password must contain at least one number.'
    }
    if ($Password -notmatch '[^A-Za-z0-9]') {
        return 'Your password must contain at least one special character (for example ! @ # %).'
    }
    return $null
}

function Add-FieldError {
    param([hashtable]$Errors, [string]$Field, [string]$Message)
    $Errors[$Field] = $Message
}

function Validate-RegistrationInput {
    param([hashtable]$Body, [string]$Mode = 'register')

    $errors = @{}
    $values = @{
        name     = (Get-FormValue -Body $Body -Name 'name')
        email    = (Get-FormValue -Body $Body -Name 'email')
        phone    = (Get-FormValue -Body $Body -Name 'phone')
        address  = (Get-FormValue -Body $Body -Name 'address')
        password = (Get-FormValue -Body $Body -Name 'password')
    }

    # --- name -----------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($values.name)) {
        Add-FieldError $errors 'name' 'Please enter your full name.'
    }
    elseif ($values.name.Length -lt 2) {
        Add-FieldError $errors 'name' 'Your name must be at least 2 characters long.'
    }
    elseif ($values.name.Length -gt 80) {
        Add-FieldError $errors 'name' 'Your name must be 80 characters or fewer.'
    }
    elseif ($values.name -notmatch "^[\p{L}'' .\-]+$") {
        Add-FieldError $errors 'name' 'Your name may only contain letters, spaces, apostrophes, periods and hyphens.'
    }

    # --- email ----------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($values.email)) {
        Add-FieldError $errors 'email' 'Please enter your email address.'
    }
    elseif (-not (Test-EmailAddress $values.email)) {
        Add-FieldError $errors 'email' 'That does not look like a valid email address. Example: juan@example.com'
    }
    else {
        $existing = Get-UserByEmail $values.email
        if ($Mode -eq 'register' -and $null -ne $existing) {
            Add-FieldError $errors 'email' 'An account with this email address already exists. Please sign in instead.'
        }
        if ($Mode -eq 'profile' -and $null -ne $existing -and $existing.id -ne $values.userId) {
            Add-FieldError $errors 'email' 'That email address is already used by another account.'
        }
    }

    # --- optional phone -------------------------------------------------
    if (-not [string]::IsNullOrWhiteSpace($values.phone) -and -not (Test-PhoneNumber $values.phone)) {
        Add-FieldError $errors 'phone' 'Please enter a valid phone number (7 to 15 digits), or leave it blank.'
    }

    # --- optional address ------------------------------------------------
    if ($values.address.Length -gt 160) {
        Add-FieldError $errors 'address' 'Your address must be 160 characters or fewer.'
    }

    return @{ Errors = $errors; Values = $values }
}

function Validate-LoginInput {
    param([hashtable]$Body)

    $errors = @{}
    $values = @{
        email    = (Get-FormValue -Body $Body -Name 'email')
        password = [string]$(if ($Body.ContainsKey('password')) { $Body['password'] } else { '' })
        next     = (Get-FormValue -Body $Body -Name 'next')
    }

    if ([string]::IsNullOrWhiteSpace($values.email)) {
        Add-FieldError $errors 'email' 'Please enter your email address.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$values.password)) {
        Add-FieldError $errors 'password' 'Please enter your password.'
    }
    return @{ Errors = $errors; Values = $values }
}

function Validate-ComplaintInput {
    param([hashtable]$Body)

    $errors = @{}
    $values = @{
        title       = (Get-FormValue -Body $Body -Name 'title')
        category    = (Get-FormValue -Body $Body -Name 'category')
        priority    = (Get-FormValue -Body $Body -Name 'priority')
        location    = (Get-FormValue -Body $Body -Name 'location')
        description = (Get-FormValue -Body $Body -Name 'description')
    }

    # --- title ----------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($values.title)) {
        Add-FieldError $errors 'title' 'Please give your report a short title.'
    }
    elseif ($values.title.Length -lt 5) {
        Add-FieldError $errors 'title' 'The title must be at least 5 characters long.'
    }
    elseif ($values.title.Length -gt 120) {
        Add-FieldError $errors 'title' 'The title must be 120 characters or fewer.'
    }

    # --- category (must be one of the allowed values) --------------------
    if ([string]::IsNullOrWhiteSpace($values.category)) {
        Add-FieldError $errors 'category' 'Please choose a category for your report.'
    }
    elseif ($global:Categories.Value -notcontains $values.category) {
        Add-FieldError $errors 'category' 'Please choose a category from the list provided.'
    }

    # --- priority --------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($values.priority)) {
        Add-FieldError $errors 'priority' 'Please choose how urgent your concern is.'
    }
    elseif ($global:Priorities.Value -notcontains $values.priority) {
        Add-FieldError $errors 'priority' 'Please choose a priority from the list provided.'
    }

    # --- location ---------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($values.location)) {
        Add-FieldError $errors 'location' 'Please tell us where the problem is located (purok, street or landmark).'
    }
    elseif ($values.location.Length -lt 3) {
        Add-FieldError $errors 'location' 'Please tell us where the problem is located. Name the purok, street or nearest landmark.'
    }
    elseif ($values.location.Length -gt 140) {
        Add-FieldError $errors 'location' 'The location must be 140 characters or fewer.'
    }

    # --- description ------------------------------------------------------
    if ([string]::IsNullOrWhiteSpace($values.description)) {
        Add-FieldError $errors 'description' 'Please describe your concern so the barangay can act on it.'
    }
    elseif ($values.description.Length -lt 20) {
        Add-FieldError $errors 'description' 'Please add a bit more detail (at least 20 characters).'
    }
    elseif ($values.description.Length -gt 2000) {
        Add-FieldError $errors 'description' 'The description must be 2,000 characters or fewer.'
    }

    # --- admin-only notes -------------------------------------------------
    if ($Body.ContainsKey('adminNotes')) {
        $notes = Get-FormValue -Body $Body -Name 'adminNotes'
        if ($notes.Length -gt 1000) {
            Add-FieldError $errors 'adminNotes' 'Notes must be 1,000 characters or fewer.'
        }
        $values['adminNotes'] = $notes
    }

    return @{ Errors = $errors; Values = $values }
}
