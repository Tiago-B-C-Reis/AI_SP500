import requests

# replace the "demo" apikey below with your own key from https://www.alphavantage.co/support/#api-key
url = 'https://www.alphavantage.co/query?function=INSIDER_TRANSACTIONS&symbol=IBM&apikey=NPFLV8LYAVIKEOBZ'
r = requests.get(url)
data = r.json()

print(data)