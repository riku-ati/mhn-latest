/**
 * MHN Latest — main.js
 * Vanilla JS, no jQuery dependency.
 */

/* =========================================================
   Helpers
   ========================================================= */

function getCsrfToken() {
  const el = document.getElementById('_csrf_token');
  return el ? el.value : '';
}

function showAlert(container, msg, type) {
  if (!container) return;
  container.className = 'alert alert-' + (type || 'info');
  container.textContent = msg;
  container.style.display = 'block';
  container.style.opacity = '1';
}

function jsonFetch(method, url, data, onSuccess, onError) {
  fetch(url, {
    method: method,
    headers: {
      'Content-Type': 'application/json',
      'X-CSRFToken': getCsrfToken()
    },
    body: data ? JSON.stringify(data) : undefined
  })
    .then(function (r) {
      if (!r.ok) {
        return r.json().then(function (j) {
          throw new Error(j.error || r.statusText);
        });
      }
      return r.json();
    })
    .then(onSuccess)
    .catch(onError);
}

/* =========================================================
   Auto-dismiss flash alerts after 5 seconds
   ========================================================= */

function initAlertDismiss() {
  document.querySelectorAll('.alert').forEach(function (alert) {
    setTimeout(function () {
      alert.style.transition = 'opacity 0.3s ease';
      alert.style.opacity = '0';
      setTimeout(function () {
        if (alert.parentNode) alert.parentNode.removeChild(alert);
      }, 350);
    }, 5000);
  });
}

/* =========================================================
   Copy-to-clipboard for elements with data-copy attribute
   Button usage: <button data-copy="#api-key-value">Copy</button>
   ========================================================= */

function initCopyButtons() {
  document.querySelectorAll('[data-copy]').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var target = document.querySelector(btn.dataset.copy);
      var text = target ? (target.value || target.textContent) : '';
      if (!text) return;
      navigator.clipboard.writeText(text.trim()).then(function () {
        var orig = btn.textContent;
        btn.textContent = 'Copied!';
        btn.style.color = 'var(--accent-green)';
        setTimeout(function () {
          btn.textContent = orig;
          btn.style.color = '';
        }, 2000);
      });
    });
  });
}

/* =========================================================
   Delete / dangerous action confirm dialogs
   Usage: <button data-confirm="Are you sure?">Delete</button>
          or <a href="..." data-confirm="...">Delete</a>
   ========================================================= */

function initConfirmDialogs() {
  document.querySelectorAll('[data-confirm]').forEach(function (el) {
    el.addEventListener('click', function (e) {
      if (!confirm(el.dataset.confirm || 'Are you sure you want to do this?')) {
        e.preventDefault();
        e.stopPropagation();
      }
    });
  });
}

/* =========================================================
   Card fade-in animation on page load
   ========================================================= */

function initCardFadeIn() {
  var cards = document.querySelectorAll('.card, .stat-card, .sensor-card, .chart-card');
  cards.forEach(function (card, i) {
    card.style.opacity = '0';
    card.style.transform = 'translateY(10px)';
    card.style.transition = 'opacity 0.3s ease ' + (i * 0.05) + 's, transform 0.3s ease ' + (i * 0.05) + 's';
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        card.style.opacity = '1';
        card.style.transform = 'translateY(0)';
      });
    });
  });
}

/* =========================================================
   Relative timestamp tooltips
   Usage: <td data-ts="2024-01-15T12:00:00">...</td>
   ========================================================= */

function initRelativeTimestamps() {
  document.querySelectorAll('[data-ts]').forEach(function (el) {
    var ts = new Date(el.dataset.ts);
    if (isNaN(ts.getTime())) return;
    var diff = Date.now() - ts.getTime();
    var secs = Math.floor(diff / 1000);
    var mins = Math.floor(secs / 60);
    var hrs = Math.floor(mins / 60);
    var days = Math.floor(hrs / 24);
    var label;
    if (days > 0) label = days + 'd ago';
    else if (hrs > 0) label = hrs + 'h ago';
    else if (mins > 0) label = mins + 'm ago';
    else label = secs + 's ago';
    el.title = label;
  });
}

/* =========================================================
   Active nav item detection fallback (URL-based)
   ========================================================= */

function initActiveNav() {
  var path = window.location.pathname;
  document.querySelectorAll('.nav-item').forEach(function (link) {
    var href = link.getAttribute('href');
    if (href && path.startsWith(href) && href !== '/') {
      link.classList.add('active');
    }
  });
}

/* =========================================================
   Search input debouncing (auto-submit forms)
   Usage: <input class="debounce-search" data-form="#my-form" ...>
   ========================================================= */

function initDebounceSearch() {
  var timers = {};
  document.querySelectorAll('.debounce-search').forEach(function (input, idx) {
    input.addEventListener('input', function () {
      clearTimeout(timers[idx]);
      timers[idx] = setTimeout(function () {
        var formSel = input.dataset.form;
        var form = formSel ? document.querySelector(formSel) : input.closest('form');
        if (form) form.submit();
      }, 300);
    });
  });
}

/* =========================================================
   LOGIN PAGE — AJAX login form
   ========================================================= */

function initLoginForm() {
  var form = document.getElementById('login-form');
  if (!form) return;

  var btn = document.getElementById('log-btn');
  var errorEl = document.getElementById('login-error');

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    if (btn) {
      btn.disabled = true;
      btn.textContent = 'Authenticating...';
    }
    if (errorEl) errorEl.style.display = 'none';

    var data = {
      email: document.getElementById('email').value,
      password: document.getElementById('passwd').value
    };

    jsonFetch('POST', '/auth/login/', data,
      function () {
        window.location.href = '/ui/dashboard/';
      },
      function (err) {
        if (btn) {
          btn.disabled = false;
          btn.textContent = 'Connect';
        }
        if (errorEl) {
          errorEl.textContent = err.message || 'Login failed.';
          errorEl.style.display = 'block';
        }
      }
    );
  });
}

/* =========================================================
   SENSOR TABLE — inline name edit, delete
   ========================================================= */

function initSensorTable() {
  var table = document.getElementById('sensor-table');
  if (!table) return;

  // Inline name edits
  table.querySelectorAll('.text-edit').forEach(function (input) {
    input.addEventListener('blur', function () {
      var sensorId = input.dataset.sensorId;
      var fieldName = input.dataset.fieldName;
      var data = {};
      data[fieldName] = input.value;
      jsonFetch('PUT', '/api/sensor/' + sensorId + '/', data,
        function () {},
        function () { alert('Could not save changes.'); }
      );
    });
  });

  // Delete sensor buttons
  table.querySelectorAll('.del-sensor').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var sensorId = btn.dataset.sensorId;
      if (!confirm('Delete this sensor? This cannot be undone.')) return;
      jsonFetch('DELETE', '/api/sensor/' + sensorId + '/', null,
        function () { window.location.reload(); },
        function () { alert('Error deleting sensor.'); }
      );
    });
  });
}

/* =========================================================
   RULE TABLE — active toggle, notes edit
   ========================================================= */

function initRuleTable() {
  var table = document.getElementById('rule-table');
  if (!table) return;

  // Active checkbox toggles
  table.querySelectorAll('.rule-toggle').forEach(function (checkbox) {
    checkbox.addEventListener('change', function () {
      var ruleId = checkbox.dataset.ruleId;
      var isChecked = checkbox.checked;
      jsonFetch('PUT', '/api/rule/' + ruleId + '/', { is_active: isChecked },
        function () {},
        function () {
          checkbox.checked = !isChecked; // revert
          alert('Could not update rule status.');
        }
      );
    });
  });

  // Notes textarea save on blur
  table.querySelectorAll('.text-edit').forEach(function (textarea) {
    textarea.addEventListener('blur', function () {
      var ruleId = textarea.dataset.ruleId;
      var fieldName = textarea.dataset.fieldName || 'notes';
      var data = {};
      data[fieldName] = textarea.value;
      jsonFetch('PUT', '/api/rule/' + ruleId + '/', data,
        function () {},
        function () { alert('Could not save changes.'); }
      );
    });
  });
}

/* =========================================================
   ADD-SENSOR PAGE — create sensor form
   ========================================================= */

function initAddSensor() {
  var createBtn = document.getElementById('create-btn');
  if (!createBtn) return;

  createBtn.addEventListener('click', function () {
    var data = {
      name: (document.getElementById('sensor-name') || document.getElementById('name') || {}).value || '',
      hostname: (document.getElementById('hostname') || {}).value || '',
      honeypot: (document.getElementById('honeypot') || {}).value || ''
    };

    var alertRow = document.getElementById('alert-row');
    var errorTxt = document.getElementById('error-txt');
    var sensorInfo = document.getElementById('sensor-info');
    if (alertRow) alertRow.style.display = 'none';

    jsonFetch('POST', '/api/sensor/', data,
      function (resp) {
        if (sensorInfo) sensorInfo.style.display = 'block';
        var idEl = document.getElementById('sensor-id');
        var secretEl = document.getElementById('sensor-secret');
        if (idEl) idEl.textContent = 'UUID: ' + resp.uuid;
        if (secretEl) secretEl.textContent = 'Secret: ' + resp.secret;
      },
      function (err) {
        if (sensorInfo) sensorInfo.style.display = 'none';
        if (alertRow) alertRow.style.display = 'block';
        if (errorTxt) errorTxt.textContent = err.message || 'Error creating sensor.';
      }
    );
  });
}

/* =========================================================
   DEPLOY / SCRIPT PAGE — save / update script
   ========================================================= */

function initScriptForm() {
  var submitBtn = document.getElementById('submit-script');
  if (!submitBtn) return;

  submitBtn.addEventListener('click', function (e) {
    e.preventDefault();
    var script = (document.getElementById('script-edit') || {}).value;
    var notes = (document.getElementById('notes-edit') || {}).value;
    var name = (document.getElementById('name-edit') || {}).value;
    var idInput = document.getElementById('id-edit');
    var id = idInput ? idInput.value : '';
    var form = document.getElementById('script-form');
    var url = form ? form.getAttribute('action') : '/api/script/';
    var method = id ? 'PUT' : 'POST';

    var alertEl = document.getElementById('script-alert');

    jsonFetch(method, url, { script: script, notes: notes, name: name, id: id },
      function (resp) {
        if (id) {
          if (alertEl) {
            alertEl.className = 'alert alert-success';
            alertEl.textContent = 'Script updated successfully.';
            alertEl.style.display = 'block';
          }
        } else {
          var scriptSelect = document.getElementById('script-select');
          var baseUrl = scriptSelect ? scriptSelect.getAttribute('action') : window.location.pathname;
          window.location = baseUrl + '?script_id=' + resp.id;
        }
      },
      function (err) {
        if (alertEl) {
          alertEl.className = 'alert alert-danger';
          alertEl.textContent = err.message || 'Error saving script.';
          alertEl.style.display = 'block';
        }
      }
    );
  });

  // Script list item click (if present in left panel)
  document.querySelectorAll('.script-list-item[data-script-id]').forEach(function (item) {
    item.addEventListener('click', function () {
      var scriptId = item.dataset.scriptId;
      var form = document.getElementById('script-select');
      var baseUrl = form ? form.getAttribute('action') : window.location.pathname;
      window.location = (baseUrl || window.location.pathname) + '?script_id=' + scriptId;
    });
  });
}

/* =========================================================
   RULE SOURCES PAGE — add / delete sources
   ========================================================= */

function initRuleSources() {
  var addBtn = document.getElementById('add-src');
  if (!addBtn) return;

  addBtn.addEventListener('click', function (e) {
    e.preventDefault();
    var name = (document.getElementById('src-name') || {}).value || '';
    var uri = (document.getElementById('src-uri') || {}).value || '';
    var note = (document.getElementById('src-note') || {}).value || '';
    var alertEl = document.getElementById('src-alert');

    jsonFetch('POST', '/api/rulesources/', { name: name, uri: uri, note: note },
      function () { window.location.reload(); },
      function (err) {
        if (alertEl) {
          alertEl.className = 'alert alert-danger';
          alertEl.textContent = err.message || 'Error adding source.';
          alertEl.style.display = 'block';
        }
      }
    );
  });

  document.querySelectorAll('.del-rs').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var rsId = btn.dataset.rsId;
      if (!confirm('Delete this rule source?')) return;
      jsonFetch('DELETE', '/api/rulesources/' + rsId + '/', null,
        function () { window.location.reload(); },
        function () { alert('Error deleting rule source.'); }
      );
    });
  });
}

/* =========================================================
   SETTINGS PAGE — add user, delete user, change password
   ========================================================= */

function initSettingsPage() {
  // Add user
  var userForm = document.getElementById('user-form');
  if (userForm) {
    userForm.addEventListener('submit', function (e) {
      e.preventDefault();
      var email = (document.getElementById('email-edit') || {}).value || '';
      var password = (document.getElementById('password-edit') || {}).value || '';
      var msgContainer = document.getElementById('msg-container');
      var alertEl = document.getElementById('user-alert');

      jsonFetch('POST', '/auth/user/', { email: email, password: password },
        function () { window.location.reload(); },
        function (err) {
          if (alertEl) {
            alertEl.className = 'alert alert-danger';
            alertEl.textContent = err.message || 'Error creating user.';
            alertEl.style.display = 'block';
          }
        }
      );
    });
  }

  // Delete user
  document.querySelectorAll('.delete-user').forEach(function (btn) {
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      if (!confirm('Delete this user?')) return;
      var userId = btn.dataset.userId;
      jsonFetch('DELETE', '/auth/user/' + userId + '/', null,
        function () { window.location.reload(); },
        function () { alert('Could not delete user.'); }
      );
    });
  });

  // Change password form
  var changePassForm = document.getElementById('change-pass-form');
  if (changePassForm) {
    var submitPass = document.getElementById('submit-pass');
    if (submitPass) {
      submitPass.addEventListener('click', function (e) {
        e.preventDefault();
        var password = (document.getElementById('password-change-edit') || {}).value || '';
        var passwordRepeat = (document.getElementById('password-repeat-edit') || {}).value || '';
        var passAlert = document.getElementById('pass-alert');

        if (password !== passwordRepeat) {
          if (passAlert) {
            passAlert.className = 'alert alert-danger';
            passAlert.textContent = 'Passwords do not match.';
            passAlert.style.display = 'block';
          }
          return;
        }

        jsonFetch('POST', changePassForm.getAttribute('action'), { password: password, password_repeat: passwordRepeat },
          function () {
            if (passAlert) {
              passAlert.className = 'alert alert-success';
              passAlert.textContent = 'Password changed successfully.';
              passAlert.style.display = 'block';
            }
          },
          function (err) {
            if (passAlert) {
              passAlert.className = 'alert alert-danger';
              passAlert.textContent = err.message || 'Error changing password.';
              passAlert.style.display = 'block';
            }
          }
        );
      });
    }
  }
}

/* =========================================================
   RESET PASSWORD REQUEST PAGE
   ========================================================= */

function initResetRequest() {
  var form = document.getElementById('reset-req-form');
  if (!form) return;

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var email = (document.getElementById('email-edit') || {}).value || '';
    var alertEl = document.getElementById('req-alert');
    var pattern = /^\w+([-+.']\w+)*@\w+([-.]\w+)*\.\w+([-.]\w+)*$/;

    if (!pattern.test(email)) {
      if (alertEl) {
        alertEl.className = 'alert alert-danger';
        alertEl.textContent = 'Please enter a valid email address.';
        alertEl.style.display = 'block';
      }
      return;
    }

    jsonFetch('POST', form.getAttribute('action'), { email: email },
      function () {
        if (alertEl) {
          alertEl.className = 'alert alert-success';
          alertEl.textContent = 'Password reset email sent. Check your inbox.';
          alertEl.style.display = 'block';
        }
      },
      function (err) {
        if (alertEl) {
          alertEl.className = 'alert alert-danger';
          alertEl.textContent = err.message || 'Error sending reset email.';
          alertEl.style.display = 'block';
        }
      }
    );
  });
}

/* =========================================================
   RESET PASSWORD PAGE (with token)
   ========================================================= */

function initResetPassword() {
  var form = document.getElementById('pass-form');
  if (!form) return;

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    var email = (document.getElementById('email-edit') || {}).value || '';
    var password = (document.getElementById('password-edit') || {}).value || '';
    var passwordRepeat = (document.getElementById('password-repeat-edit') || {}).value || '';
    var hashStr = (document.getElementById('hashstr-edit') || {}).value || '';
    var alertEl = document.getElementById('pass-alert');

    if (password !== passwordRepeat) {
      if (alertEl) {
        alertEl.className = 'alert alert-danger';
        alertEl.textContent = 'Passwords do not match.';
        alertEl.style.display = 'block';
      }
      return;
    }

    jsonFetch('POST', '/auth/changepass/', { email: email, password: password, password_repeat: passwordRepeat, hashstr: hashStr },
      function () { window.location.href = '/'; },
      function (err) {
        if (alertEl) {
          alertEl.className = 'alert alert-danger';
          alertEl.textContent = err.message || 'Error resetting password.';
          alertEl.style.display = 'block';
        }
      }
    );
  });
}

/* =========================================================
   ATTACKS PAGE — row click to filter by source IP
   ========================================================= */

function initAttacksTable() {
  var table = document.getElementById('attacks-table');
  if (!table) return;

  table.querySelectorAll('tbody tr[data-ip]').forEach(function (row) {
    row.style.cursor = 'pointer';
    row.addEventListener('click', function () {
      var ip = row.dataset.ip;
      if (ip) {
        var params = new URLSearchParams(window.location.search);
        params.set('source_ip', ip);
        window.location.search = params.toString();
      }
    });
  });
}

/* =========================================================
   Honeypot badge colour helper (applied dynamically)
   ========================================================= */

function initHoneypotBadges() {
  document.querySelectorAll('[data-hp]').forEach(function (el) {
    var hp = (el.dataset.hp || '').toLowerCase();
    if (hp.includes('cowrie')) el.classList.add('hp-cowrie');
    else if (hp.includes('dionaea')) el.classList.add('hp-dionaea');
    else if (hp.includes('kippo')) el.classList.add('hp-kippo');
    else if (hp.includes('glastopf')) el.classList.add('hp-glastopf');
    else if (hp.includes('snort')) el.classList.add('hp-snort');
    else if (hp.includes('suricata')) el.classList.add('hp-suricata');
    else if (hp.includes('conpot')) el.classList.add('hp-conpot');
    else el.classList.add('hp-other');
  });
}

/* =========================================================
   Boot — run all inits on DOMContentLoaded
   ========================================================= */

document.addEventListener('DOMContentLoaded', function () {
  initAlertDismiss();
  initCopyButtons();
  initConfirmDialogs();
  initCardFadeIn();
  initRelativeTimestamps();
  initActiveNav();
  initDebounceSearch();

  // Page-specific
  initLoginForm();
  initSensorTable();
  initRuleTable();
  initAddSensor();
  initScriptForm();
  initRuleSources();
  initSettingsPage();
  initResetRequest();
  initResetPassword();
  initAttacksTable();
  initHoneypotBadges();
});
