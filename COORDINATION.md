# MHN-Latest Build Coordination

## Agents & Responsibilities
- **Agent-Backend** (Agent 1): Python 3 server code — app/__init__.py, api/, auth/, common/, tasks/, collector.py, manage.py, initdatabase.py, mhn.py, config.py.template
- **Agent-Frontend** (Agent 2): All HTML templates + CSS + JS — templates/base.html, templates/ui/*, templates/security/*, static/css/style.css, static/js/main.js
- **Agent-Infra** (Agent 3): requirements.txt, scripts/ (copy from mhn/scripts/), README.md, Dockerfile, docker-compose.yml

## Communication Protocol
Each agent MUST update this file when it completes a section by appending to the Status Log below.
Agents should read this file before starting to check what other agents have done.

## Shared Interfaces (template context variables)
Backend passes these to templates — Frontend agent MUST honour them exactly.

### dashboard.html context
- `attackcount` (int)
- `top_attackers` (list of {source_ip, count})
- `top_ports` (list of {destination_port, count})
- `top_hp` (list of {honeypot, count})
- `top_sensor` (list of {identifier, count})
- `freq_sigs` (list of {signature, count})
- `get_sensor_name(identifier)` → str
- `get_flag_ip(ip)` → URL string

### attacks.html context
- `attacks` (paginated list, each has: source_ip, source_port, destination_port, honeypot, timestamp, identifier)
- `sensors` (Sensor queryset)
- `get_flag_ip`, `get_sensor_name`
- `view` = 'ui.get_attacks'
- URL params: source_ip, honeypot, identifier (for filtering)

### feeds.html context
- `feeds` (paginated hpfeed objects, each has .payload as dict)
- `columns` (list of column names for selected channel)
- `channel_list` (list of all channel names)
- `view` = 'ui.get_feeds'

### sensors.html context
- `sensors` (paginated Sensor objects: uuid, name, honeypot, ip, hostname, created_date, attacks_count)
- `view` = 'ui.get_sensors'

### rules.html context
- `rules` (paginated (Rule, nrevs) tuples)
- `view` = 'ui.get_rules'
- URL param: sig_name (search filter)

### script.html context
- `scripts` (all DeployScript objects ordered by date)
- `script` (current DeployScript: id, name, script text, notes, date, user.email)

### settings.html context
- `users` (active User objects with: email, active)
- `apikey` (ApiKey object with .api_key attribute)

### chart.html
- SVG image endpoints: /image/top_passwords.svg, /image/top_users.svg, /image/top_combos.svg, /image/top_sessions.svg

### honeymap.html
- No template vars — embeds external honeymap

### add-sensor.html
- No template vars — just shows deploy instructions and API key

### reset-password.html
- `reset_user` (User object with .email)
- `hashstr` (string token)

### reset-request.html
- No vars

## Jinja2 Filters & Context Processors
- `{{ value | fdate }}` — formats datetime (defined in common/templatetags.py)
- `{{ value | number_format }}` — formats int with commas
- `current_user` — available in all templates (Flask-Security context processor)
- `config` — Flask config dict available via context processor

## URL Routes (for template url_for() calls)
- `url_for('ui.dashboard')` — main dashboard
- `url_for('ui.get_attacks')` — attacks list
- `url_for('ui.get_feeds')` — feeds list
- `url_for('ui.get_sensors')` — sensors list
- `url_for('ui.add_sensor')` — add sensor page
- `url_for('ui.get_rules')` — rules list
- `url_for('ui.rule_sources_mgmt')` — rule sources
- `url_for('ui.deploy_mgmt')` — deploy scripts
- `url_for('ui.honeymap')` — honeymap
- `url_for('ui.settings')` — settings/users
- `url_for('ui.chart')` — charts
- `url_for('auth.login_user')` — login
- `url_for('auth.logout_user')` — logout
- `url_for('auth.change_password')` — change password
- `url_for('api.get_sensors')` — JSON sensors API
- `url_for('api.create_sensor')` — create sensor API

## Status Log
| Agent | Section | Status | Notes |
|-------|---------|--------|-------|
| Agent-Backend | Initialization | 🔄 In Progress | Reading source files |
| Agent-Frontend | All templates + CSS + JS | ✅ Done | Wrote 19 files (17 templates, 1 CSS, 1 JS) |
| Agent-Infra | Initialization | ⏳ Waiting | Ready to start |
| Agent-Infra | requirements + scripts + Docker + README + gap-fill | ✅ Done | All infrastructure files written |
| Agent-Backend | All Python files | ✅ Done | Wrote 32 files |
