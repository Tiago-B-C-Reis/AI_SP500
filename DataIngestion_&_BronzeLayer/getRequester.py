import csv
import json
import os
import requests
import helperFunctions as h
from ast import List
from tokenize import String
from io import StringIO
from pathlib import Path
from typing import Iterable
from dotenv import load_dotenv


# Core Stock APIs
sp500_tickers_path = Path(__file__).parent / "Data" / "sp500_tickers.csv"
sp500_tickers = []
with open(sp500_tickers_path, newline='', encoding='utf-8') as csvfile:
    csv_reader = csv.DictReader(csvfile)
    for row in csv_reader:
        sp500_tickers.append(row["ticker"])

#print(sp500_tickers)

api_urls_path = Path(__file__).parent / "Data" / "alpha_vantage_urls.json"
with open(api_urls_path, encoding='utf-8') as jsonfile:
    data = json.load(jsonfile)
    api_urls = data.get("Core Stock APIs", [])

#print(api_urls)

# Collect only the "params" dicts from each API definition
params_list = [api.get("params", {}) for api in api_urls]
#print(params_list[0])
    
for category_name, endpoints in data.items():
    for endpoint in endpoints:
        base_url = endpoint["base_url"]

        for symbol in sp500_tickers:
            params = endpoint["params"].copy()
            params["symbol"] = symbol
            
            print(f"Calling → {params.get('function')} for {symbol}")
            
            # if you want to build the full URL manually:
            query_string = "&".join(f"{k}={v}" for k, v in params.items())
            full_url = f"{base_url}{query_string}"
            print(f"Full URL: {full_url}")
            
"""    
    for endpoint in endpoints:
        base_url = endpoint["base_url"]
        params = endpoint["params"]

        print(f"Calling: {params.get('function')} ({params})")
        
        data = h.make_request(base_url, params)
        
        # Process or store the data (printing only metadata for now)
        print("Response keys:", list(data.keys())[:3], "...\n")
        """
