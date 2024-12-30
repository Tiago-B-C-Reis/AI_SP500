import requests

# TIME_SERIES_DAILY
# This API returns raw (as-traded) daily time series (date, daily open, daily high,
# daily low, daily close, daily volume) of the global equity specified
url = 'https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&symbol=IBM&apikey=YUM3YMPEO7OWEX7Q&datatype=json'
r = requests.get(url)
data = r.text
print(data)