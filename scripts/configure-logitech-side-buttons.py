#!/usr/bin/env python3
"""Configure only Moonlight's two side-button slots; never export the settings DB."""
import copy
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import uuid

bundle = 'com.moonlight-stream.Moonlight'
agent = '/Library/LaunchAgents/com.logi.optionsplus.plist'
domain = f'gui/{os.getuid()}'
db = Path.home() / 'Library/Application Support/LogiOptionsPlus/settings.db'
if not db.is_file():
    raise SystemExit('Logi Options+ settings database not found.')
was_loaded = subprocess.run(['launchctl', 'print', domain + '/com.logi.cp-dev-mgr'], capture_output=True).returncode == 0
if was_loaded:
    subprocess.run(['launchctl', 'bootout', domain, agent], check=True)
try:
    connection = sqlite3.connect(str(db), timeout=10)
    with connection:
        connection.execute('BEGIN IMMEDIATE')
        row = connection.execute('SELECT _id,file FROM data ORDER BY _id DESC LIMIT 1').fetchone()
        data = json.loads(row[1])
        apps = data['applications']['applications']
        application = next((a for a in apps if a.get('bundleId') == bundle), None)
        default = next(data[k] for k in data['profile_keys'] if data[k].get('name') == 'PROFILE_NAME_DEFAULT')
        if application is None:
            app_id = str(uuid.uuid4())
            application = {'applicationId': app_id, 'databaseId': app_id, 'name': 'Moonlight',
                           'applicationPath': '/Applications/Moonlight.app',
                           'applicationPathsList': ['/Applications/Moonlight.app'],
                           'bundleId': bundle, 'isInstalled': True}
            apps.append(application)
        app_id = application['applicationId']
        profile_key = next((k for k in data['profile_keys'] if data[k].get('applicationId') == app_id), None)
        if profile_key is None:
            profile_key = 'profile-' + app_id
            data[profile_key] = copy.deepcopy(default)
            data[profile_key].update(id=app_id, applicationId=app_id, name='Moonlight', activeForApplication=True)
            data['profile_keys'].append(profile_key)
        profile = data[profile_key]
        changed = []
        # These are the two side controls of the Signature M750. code is the
        # USB keyboard usage, as used by Logi Options+'s KEYSTROKE schema.
        for assignment in profile['assignments']:
            slot = assignment.get('slotId', '')
            number = 13 if slot == 'signature-m750-2b02c_c83' else 14 if slot == 'signature-m750-2b02c_c86' else None
            if number is None:
                continue
            card_id = 'card_global_presets_keyboard_shortcut'
            assignment['cardId'] = card_id
            assignment['card'] = {
                'attribute': 'MACRO_PLAYBACK', 'continuous': False, 'id': card_id,
                'macro': {'type': 'KEYSTROKE', 'actionName': f'F{number}',
                          'keystroke': {'code': 104 + number - 13, 'modifiers': [], 'virtualKeyId': f'VK_F{number}'}},
                'name': f'MoonDock side button {number - 9}', 'readOnly': False,
                'tags': ['PRESET_TAG_KEY_OR_BUTTON'],
            }
            changed.append(number)
        if sorted(changed) != [13, 14]:
            raise RuntimeError('Expected both Signature M750 side-button slots; transaction cancelled.')
        connection.execute('UPDATE data SET file=? WHERE _id=?',
                           (json.dumps(data, separators=(',', ':')).encode(), row[0]))
    connection.close()
    print('Configured Moonlight-only side buttons F13/F14. Scroll/global assignments unchanged.')
finally:
    if was_loaded:
        subprocess.run(['launchctl', 'bootstrap', domain, agent], check=True)
