import sys
import json
from fetch_livechart import get_cookies_firefox
import urllib.request
from bs4 import BeautifulSoup

url = "https://www.livechart.me/schedule"
req = urllib.request.Request(url)
req.add_header('User-Agent', 'Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0')

cookie_str = get_cookies_firefox()
if cookie_str:
    req.add_header('Cookie', cookie_str)

opener = urllib.request.build_opener()
response = opener.open(req, timeout=15)
html = response.read().decode('utf-8')

soup = BeautifulSoup(html, 'html.parser')
days = soup.find_all('div', class_='lc-timetable-day')
print(f"Found {len(days)} days")
for day in days:
    header = day.find('h2')
    print("Day header:", header.text.strip() if header else day.get('id', 'Unknown'))
