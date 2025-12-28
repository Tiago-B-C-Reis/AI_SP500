import requests
import json

# replace the "demo" apikey below with your own key from https://www.alphavantage.co/support/#api-key
url = 'https://www.alphavantage.co/query'
params = {
    'function': 'NEWS_SENTIMENT',
    'time_from': '20251225T0130',
    'sort': 'RELEVANCE',
    'limit': '25',
    'apikey': 'NPFLV8LYAVIKEOBZ'
}
r = requests.get(url, params=params)
data = r.json()

with open('DataIngestion/Data/news_sentiment.json', 'w') as f:
    json.dump(data, f, indent=4)