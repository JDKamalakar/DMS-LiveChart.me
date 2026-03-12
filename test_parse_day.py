import urllib.request
from bs4 import BeautifulSoup
import json

req = urllib.request.Request("https://www.livechart.me/schedule")
req.add_header('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0')

try:
    html = urllib.request.urlopen(req, timeout=10).read().decode('utf-8')
    soup = BeautifulSoup(html, 'html.parser')

    days = soup.find_all('div', class_='lc-timetable-day')
    print(f"Found {len(days)} days")
    for day in days[:3]:
        header = day.find('h2')
        print("Day Header:", header.text.strip() if header else "Unknown")
        slots = day.find_all('div', class_='lc-timetable-timeslot')
        print("Slots in this day:", len(slots))
except Exception as e:
    print(e)
