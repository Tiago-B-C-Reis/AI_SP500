import requests
import pandas as pd
import time

# Yahoo Finance API-like endpoint for historical data of S&P 500 (^GSPC)
url = 'https://query1.finance.yahoo.com/v10/finance/quoteSummary/%5EGSPC?formatted=true&modules=price,summaryDetail,quoteUnadjustedPerformanceOverview&lang=en-US&region=US'

# Function to make a request and retry if rate-limited
def fetch_data(url, max_retries=5, delay=10):
    for i in range(max_retries):
        response = requests.get(url)
        
        if response.status_code == 200:
            return response.json()  # Success
        elif response.status_code == 429:
            print(f"Rate-limited. Retrying in {delay} seconds...")
            time.sleep(delay)  # Wait before retrying
        else:
            print(f"Failed to retrieve data. Status code: {response.status_code}")
            break
    return None  # Return None if all retries fail

# Fetch data with retries
data = fetch_data(url)

if data:
    # Navigate through the JSON structure
    result = data['quoteSummary']['result'][0]
    performance = result['quoteUnadjustedPerformanceOverview']['performanceOverview']

    # Create a dictionary for the DataFrame
    performance_dict = {
        'As of Date': [performance['asOfDate']['fmt']],
        '5 Days Return': [performance['fiveDaysReturn']['fmt']],
        '1 Month Return': [performance['oneMonthReturn']['fmt']],
        '3 Month Return': [performance['threeMonthReturn']['fmt']],
        '6 Month Return': [performance['sixMonthReturn']['fmt']],
        'YTD Return': [performance['ytdReturnPct']['fmt']],
        '1 Year Total Return': [performance['oneYearTotalReturn']['fmt']],
        '2 Year Total Return': [performance['twoYearTotalReturn']['fmt']],
        '3 Year Total Return': [performance['threeYearTotalReturn']['fmt']],
        '5 Year Total Return': [performance['fiveYearTotalReturn']['fmt']],
        '10 Year Total Return': [performance['tenYearTotalReturn']['fmt']],
        'Max Return': [performance['maxReturn']['fmt']]
    }

    # Convert dictionary to Pandas DataFrame
    df = pd.DataFrame(performance_dict)

    # Print the DataFrame
    print(df)
else:
    print("Failed to retrieve data after retries.")
