import urllib.request
from bs4 import BeautifulSoup
from fetch_livechart import get_cookies_firefox

url = "https://www.livechart.me/schedule/tv"
req = urllib.request.Request(url)
req.add_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0')

cookie_str = get_cookies_firefox()
if cookie_str: req.add_header('Cookie', cookie_str)

opener = urllib.request.build_opener()
response = opener.open(req, timeout=15)
html = response.read().decode('utf-8')

soup = BeautifulSoup(html, 'html.parser')
days = soup.find_all('div', class_='lc-timetable-day')
for day in days[:2]:
    header = day.find('h2')
    h2_text = header.text.strip() if header else 'Unknown'
    # "Sun\n          Mar 8" usually
    print("Day:", repr(h2_text))
    slots = day.find_all('div', class_='lc-timetable-timeslot')
    print("Slots count:", len(slots))
