import requests

# replace the "demo" apikey below with your own key from https://www.alphavantage.co/support/#api-key
url = 'https://www.alphavantage.co/query?function=ANALYTICS_FIXED_WINDOW&SYMBOLS=NVDA&OHLC=close&INTERVAL=DAILY&CALCULATIONS=MIN,MAX,MEAN&apikey=NPFLV8LYAVIKEOBZ'
r = requests.get(url)
data = r.json()

#print(data)

import datetime

# Get the week number as a string (e.g., "01", "34", "52")
week_string = "Week_" + datetime.date.today().strftime("%V")
print(f"Current Week: {week_string}")

today = datetime.date.today()
iso_year_week = f"{today.year}-W{today.strftime('%V')}"
print(f"ISO Year-Week: {iso_year_week}")
