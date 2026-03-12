import browser_cookie3

try:
    cj = browser_cookie3.chrome(domain_name='livechart.me')
    print("Chrome success:", len(cj))
except Exception as e:
    print("Chrome failed:", str(e))

try:
    cj = browser_cookie3.firefox(domain_name='livechart.me')
    print("Firefox success:", len(cj))
except Exception as e:
    print("Firefox failed:", str(e))
