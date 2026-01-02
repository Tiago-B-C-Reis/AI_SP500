import os
import json
import csv
import sys
import time
import requests
from pathlib import Path

# Add project root to sys.path to allow for absolute imports
sys.path.append(str(Path(__file__).resolve().parents[1]))
import Helper_Functions.ingestion as ingestion
from Helper_Functions.logger import log_to_postgres
from typing import List
from dotenv import load_dotenv

SCRIPT_DIR = Path(__file__).resolve().parent
dotenv_path = SCRIPT_DIR.parent / ".env"
load_dotenv(dotenv_path)

def get_sp500_tickers() -> list[str]:
    """Reads S&P 500 tickers from a CSV file."""
    sp500_tickers_path = Path(__file__).parent / "Data" / "sp500_tickers.csv"
    tickers = []
    with open(sp500_tickers_path, newline='', encoding='utf-8') as csvfile:
        csv_reader = csv.DictReader(csvfile)
        for row in csv_reader:
            tickers.append(row["ticker"])
    return tickers


if __name__ == "__main__":
    calculation_groups = [
            "MIN,MAX,MEAN",
            "MEDIAN,CUMULATIVE_RETURN,MAX_DRAWDOWN",
            "VARIANCE(annualized=True),STDDEV(annualized=True),HISTOGRAM(bins=10)"
        ]
    base_url = 'https://www.alphavantage.co/query?'
    apikey = os.environ.get("ALPHA_VANTAGE_API_KEY")

    sp500_tickers = get_sp500_tickers()
    for ticker in sp500_tickers:
        combined_data = {}
        for calcs in calculation_groups:
            params = {
                'function': "ANALYTICS_FIXED_WINDOW",
                'SYMBOLS': ticker,
                'RANGE': "1year",
                'OHLC': "close",
                'INTERVAL': "DAILY",
                'CALCULATIONS': calcs,
                'apikey': apikey
            }
            # Make the request
            response = ingestion.get_json_response(base_url, params, sleep_time=1)

            if 'payload' in response:
                for sym, values in response['payload'].items():
                    combined_data.setdefault(sym, {}).update(values)
            print(combined_data)
