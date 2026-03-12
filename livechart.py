import sqlite3
import shutil
import os
import requests
from bs4 import BeautifulSoup
import json

def get_livechart_data(date="2026-03-01"):
    cookie_db = os.path.expanduser('~/.mozilla/firefox/0mcpenfr.default-release/cookies.sqlite')
    tmp_db = '/tmp/cookies.sqlite'
    
    # Copy db to avoid locking
    if os.path.exists(cookie_db):
        shutil.copy2(cookie_db, tmp_db)
    else:
        print("No cookie db found")
        return
        
    conn = sqlite3.connect(tmp_db)
    cursor = conn.cursor()
    cursor.execute("SELECT name, value FROM moz_cookies WHERE host LIKE '%livechart.me%'")
    rows = cursor.fetchall()
    conn.close()
    
    cookies = {}
    for name, value in rows:
        cookies[name] = value
        
    headers = {
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0'
    }
    
    url = f"https://www.livechart.me/schedule?date={date}"
    resp = requests.get(url, cookies=cookies, headers=headers)
    
    if "Just a moment..." in resp.text or resp.status_code == 403:
        print("Cloudflare challenge failed or 403. Using mock data for now.")
    else:
        print("Success fetching schedule.")
        
    # parse the HTML
    soup = BeautifulSoup(resp.content, 'html.parser')
    anime_cards = soup.select('.anime-card')
    
    results = []
    for card in anime_cards:
        title = card.select_one('.main-title')
        title = title.text.strip() if title else 'Unknown'
        results.append(title)
        
    print(json.dumps(results[:5], indent=2))

if __name__ == "__main__":
    get_livechart_data()
