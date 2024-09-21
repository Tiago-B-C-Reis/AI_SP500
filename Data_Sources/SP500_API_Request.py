import yfinance as yf

# Define the S&P 500 ticker symbol
sp500_symbol = "^GSPC"

# Create a Ticker object for S&P 500
sp500_ticker = yf.Ticker(sp500_symbol)

# Fetch historical market data for S&P 500
historical_data_sp500 = sp500_ticker.history(period="1y")  # data for the last year
print("Historical Data for S&P 500:")
print(historical_data_sp500)

# Fetch basic financials (if available, S&P 500 doesn't have financials like individual stocks)
# S&P 500 is an index, so financials like individual companies won't be available
# financials_sp500 = sp500_ticker.financials
# print("\nFinancials for S&P 500:")
# print(financials_sp500)

# Fetch stock actions like dividends and splits (for indices, this may not be applicable)
actions_sp500 = sp500_ticker.actions
print("\nStock Actions for S&P 500:")
print(actions_sp500)
