import requests

# replace the "demo" apikey below with your own key from https://www.alphavantage.co/support/#api-key
url = 'https://www.alphavantage.co/query?function=ANALYTICS_FIXED_WINDOW&SYMBOLS=ETR&RANGE=1year&OHLC=close&INTERVAL=DAILY&CALCULATIONS=MIN,MAX,MEAN&apikey=NPFLV8LYAVIKEOBZ'
r = requests.get(url)
data = r.json()

print(data)