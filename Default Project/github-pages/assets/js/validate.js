/* ==========================================================================
   validate.js - input validation
   Every rule returns a friendly message. Fields are checked independently so a
   form reports all its problems at once instead of one at a time.
   ========================================================================== */
window.App = window.App || {};

(function (App) {
  'use strict';

  var EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;

  function isEmail(value) {
    if (!value) return false;
    if (value.length > 190) return false;
    return EMAIL_RE.test(value);
  }

  function isPhone(value) {
    if (!value || !String(value).trim()) return true;   // optional
    var digits = String(value).replace(/[^0-9]/g, '');
    return digits.length >= 7 && digits.length <= 15;
  }

  /** Returns an error message, or null when the password is acceptable. */
  function passwordPolicy(password) {
    if (!password) return 'Please choose a password.';
    if (password.length < 8) return 'Your password must be at least 8 characters long.';
    if (password.length > 128) return 'Your password is too long (maximum 128 characters).';
    if (!/[A-Za-z]/.test(password)) return 'Your password must contain at least one letter.';
    if (!/[0-9]/.test(password)) return 'Your password must contain at least one number.';
    if (!/[^A-Za-z0-9]/.test(password)) return 'Your password must contain at least one special character (for example ! @ # %).';
    return null;
  }

  function passwordScore(password) {
    if (!password) return 0;
    var s = 0;
    if (password.length >= 8) s++;
    if (password.length >= 12) s++;
    if (/[a-z]/.test(password) && /[A-Z]/.test(password)) s++;
    if (/[0-9]/.test(password)) s++;
    if (/[^A-Za-z0-9]/.test(password)) s++;
    return Math.min(s, 4);
  }

  function isValidName(name) {
    return !!name && name.trim().length >= 2 && name.trim().length <= 80;
  }

  // ------------------------------------------------------------- register --
  function validateRegistration(input, mode) {
    var errors = {};
    var values = {
      name: (input.name || '').trim(),
      email: (input.email || '').trim(),
      phone: (input.phone || '').trim(),
      address: (input.address || '').trim(),
      password: input.password || ''
    };

    if (!values.name) {
      errors.name = 'Please enter your full name.';
    } else if (values.name.length < 2) {
      errors.name = 'Your name must be at least 2 characters long.';
    } else if (values.name.length > 80) {
      errors.name = 'Your name must be 80 characters or fewer.';
    }

    if (!values.email) {
      errors.email = 'Please enter your email address.';
    } else if (!isEmail(values.email)) {
      errors.email = 'That does not look like a valid email address. Example: juan@example.com';
    } else {
      var existing = App.Store.userByEmail(values.email);
      if (mode === 'register' && existing) {
        errors.email = 'An account with this email address already exists. Please sign in instead.';
      }
      if (mode === 'profile' && existing && mode !== 'register' && existing.id !== input.userId) {
        errors.email = 'That email address is already used by another account.';
      }
    }

    if (values.phone && !isPhone(values.phone)) {
      errors.phone = 'Please enter a valid phone number (7 to 15 digits), or leave it blank.';
    }
    if (values.address.length > 160) {
      errors.address = 'Your address must be 160 characters or fewer.';
    }

    var policy = passwordPolicy(values.password);
    if (policy) errors.password = policy;

    return { errors: errors, values: values };
  }

  // ------------------------------------------------------------- complaint --
  function validateComplaint(input) {
    var errors = {};
    var values = {
      title: (input.title || '').trim(),
      category: (input.category || '').trim(),
      priority: (input.priority || '').trim(),
      location: (input.location || '').trim(),
      description: (input.description || '').trim(),
      adminNotes: (input.adminNotes || '').trim()
    };

    if (!values.title) {
      errors.title = 'Please give your report a short title.';
    } else if (values.title.length < 5) {
      errors.title = 'The title must be at least 5 characters long.';
    } else if (values.title.length > 120) {
      errors.title = 'The title must be 120 characters or fewer.';
    }

    if (!values.category) {
      errors.category = 'Please choose a category for your report.';
    } else if (!has(App.Store.CATEGORIES, values.category)) {
      errors.category = 'Please choose a category from the list provided.';
    }

    if (!values.priority) {
      errors.priority = 'Please choose how urgent your concern is.';
    } else if (!has(App.Store.PRIORITIES, values.priority)) {
      errors.priority = 'Please choose a priority from the list provided.';
    }

    if (!values.location) {
      errors.location = 'Please tell us where the problem is located (purok, street or landmark).';
    } else if (values.location.length < 3) {
      errors.location = 'Please tell us where the problem is located. Name the purok, street or nearest landmark.';
    } else if (values.location.length > 140) {
      errors.location = 'The location must be 140 characters or fewer.';
    }

    if (!values.description) {
      errors.description = 'Please describe your concern so the barangay can act on it.';
    } else if (values.description.length < 20) {
      errors.description = 'Please add a bit more detail (at least 20 characters).';
    } else if (values.description.length > 2000) {
      errors.description = 'The description must be 2,000 characters or fewer.';
    }

    if (values.adminNotes.length > 1000) {
      errors.adminNotes = 'Notes must be 1,000 characters or fewer.';
    }

    return { errors: errors, values: values };
  }

  function has(list, value) {
    for (var i = 0; i < list.length; i++) if (list[i].value === value) return true;
    return false;
  }

  App.Validate = {
    isEmail: isEmail,
    isPhone: isPhone,
    passwordPolicy: passwordPolicy,
    passwordScore: passwordScore,
    isValidName: isValidName,
    validateRegistration: validateRegistration,
    validateComplaint: validateComplaint
  };
})(window.App);