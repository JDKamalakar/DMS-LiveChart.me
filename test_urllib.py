import urllib.request
import urllib.parse
from http.cookiejar import CookieJar, Cookie
import sqlite3
import shutil
import os

cookie_db = os.path.expanduser('~/.mozilla/firefox/0mcpenfr.default-release/cookies.sqlite')
tmp_db = '/tmp/cookies.sqlite'
if os.path.exists(cookie_db):
    shutil.copy2(cookie_db, tmp_db)
    
cj = CookieJar()
conn = sqlite3.connect(tmp_db)
cursor = conn.cursor()
cursor.execute("SELECT name, value, host, path, expiry, isSecure FROM moz_cookies WHERE host LIKE '%livechart.me%'")
for name, value, host, path, expiry, isSecure in cursor.fetchall():
    c = Cookie(0, name, value, None, False, host, host.startswith('.'), host.startswith('.'), path, True, isSecure, expiry, False, None, None, {})
    cj.set_cookie(c)
conn.close()

opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
opener.addheaders = [('User-agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')]

try:
    response = opener.open("https://www.livechart.me/schedule?date=2026-03-01", timeout=10)
    html = response.read().decode('utf-8')
    print("Length:", len(html))
    with open("livechart.html", "w") as f:
        f.write(html)
except Exception as e:
    print(e)
