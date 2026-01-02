import requests
import json
from datetime import datetime, timedelta

# replace the "demo" apikey below with your own key from https://www.alphavantage.co/support/#api-key
url = 'https://www.alphavantage.co/query'
params = {
    'function': 'NEWS_SENTIMENT',
    'time_from': (datetime.now() - timedelta(days=1)).strftime('%Y%m%dT%H%M'),
    'sort': 'RELEVANCE',
    'limit': '1000',
    'apikey': 'NPFLV8LYAVIKEOBZ'
}
r = requests.get(url, params=params)
data = r.json()

with open('DataIngestion/Data/news_sentiment.json', 'w') as f:
    json.dump(data, f, indent=4)