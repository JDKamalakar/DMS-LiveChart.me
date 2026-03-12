import json
import fetch_livechart

# Need to monkeypatch browser running or just print JSON
try:
    print(fetch_livechart.main("2026-03-01", "firefox"))
except Exception as e:
    print("Error:", e)
