import yfinance as yf
from datetime import datetime, timedelta

# Define recent dates within the last 30 days
end_date = datetime.today()
start_date = end_date - timedelta(days=7)

# Fetch data for Apple stock
aapl = yf.Ticker("AAPL")
aapl_historical = aapl.history(start=start_date.strftime("%Y-%m-%d"),
                               end=end_date.strftime("%Y-%m-%d"),
                               interval="30m")
print(aapl_historical)

