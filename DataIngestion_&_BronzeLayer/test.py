import os
from pathlib import Path
import requests
from dotenv import load_dotenv
import csv
import json


SCRIPT_DIR = Path(__file__).resolve().parent
load_dotenv(SCRIPT_DIR / ".env")
load_dotenv()  # Fallback to project-root .env if available
API_NINJA = os.environ.get("API_NINJA")

api_url = 'https://api.api-ninjas.com/v1/sp500'
response = requests.get(api_url, headers={'X-Api-Key': API_NINJA})

data = json.loads(response.text)
tickers = [row["ticker"] for row in data]
print(tickers)
    
fieldnames = list(data[0].keys())

with open(SCRIPT_DIR / "sp500_tickers.csv", "w", newline="") as csvfile:
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    writer.writeheader()
    for row in data:
        writer.writerow(row)
