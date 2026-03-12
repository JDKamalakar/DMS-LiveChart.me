import sqlite3
import shutil
import os
import requests
import json

cookie_db = os.path.expanduser('~/.mozilla/firefox/0mcpenfr.default-release/cookies.sqlite')
tmp_db = '/tmp/cookies.sqlite'
if os.path.exists(cookie_db):
    shutil.copy2(cookie_db, tmp_db)
    conn = sqlite3.connect(tmp_db)
    cursor = conn.cursor()
    cursor.execute("SELECT name, value FROM moz_cookies WHERE host LIKE '%livechart.me%'")
    cookies = {name: value for name, value in cursor.fetchall()}
    conn.close()
    
    headers = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0'}
    resp = requests.get("https://www.livechart.me/schedule?date=2026-03-01", cookies=cookies, headers=headers)
    
    if "Just a moment..." in resp.text:
        print("Cloudflare challenged.")
    else:
        print("Success! len:", len(resp.text))
        with open("livechart.html", "w") as f:
            f.write(resp.text)
else:
    print("No DB")
