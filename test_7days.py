import sys
import json
import urllib.request
from bs4 import BeautifulSoup
import datetime
import concurrent.futures

from fetch_livechart import get_cookies_firefox

cookie_str = get_cookies_firefox()

def fetch_date(date_str):
    url = f"https://www.livechart.me/schedule?date={date_str}"
    req = urllib.request.Request(url)
    req.add_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0')
    if cookie_str: req.add_header('Cookie', cookie_str)
    try:
        html = urllib.request.urlopen(req, timeout=10).read().decode('utf-8')
        soup = BeautifulSoup(html, 'html.parser')
        return date_str, len(soup.find_all('div', class_='lc-timetable-timeslot'))
    except Exception as e:
        return date_str, str(e)

base = datetime.datetime.strptime("2026-03-01", "%Y-%m-%d")
dates = [(base + datetime.timedelta(days=i)).strftime("%Y-%m-%d") for i in range(7)]

with concurrent.futures.ThreadPoolExecutor(max_workers=7) as executor:
    results = executor.map(fetch_date, dates)

for date, count in results:
    print(f"{date}: {count} slots")
