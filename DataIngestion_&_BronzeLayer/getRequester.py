import csv
import json
from pathlib import Path

import requests

import helperFunctions as h
from typing import List
from dotenv import load_dotenv


def get_sp500_tickers() -> list[str]:
    """Reads S&P 500 tickers from a CSV file."""
    sp500_tickers_path = Path(__file__).parent / "Data" / "sp500_tickers.csv"
    tickers = []
    with open(sp500_tickers_path, newline='', encoding='utf-8') as csvfile:
        csv_reader = csv.DictReader(csvfile)
        for row in csv_reader:
            tickers.append(row["ticker"])
    return tickers

def get_api_urls() -> dict:
    """Reads API URLs from a JSON file."""
    api_urls_path = Path(__file__).parent / "Data" / "alpha_vantage_urls.json"
    with open(api_urls_path, encoding='utf-8') as jsonfile:
        return json.load(jsonfile)

sp500_tickers = get_sp500_tickers()
data = get_api_urls()


if __name__ == "__main__":
    # Iterate over each API endpoint and make requests for each ticker
    for category_name, endpoints in data.items():
        for endpoint in endpoints:
            base_url = endpoint["base_url"]

            for symbol in sp500_tickers:
                params = endpoint["params"].copy()
                params["symbol"] = symbol

                print(f"Calling → {params.get('function')} for {symbol}")
                response = h.get_json_response(base_url, params)
                h.load_to_s3(response)