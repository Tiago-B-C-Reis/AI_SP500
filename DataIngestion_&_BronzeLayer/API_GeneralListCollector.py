import csv
import json
import os
import requests
from ast import List
from tokenize import String
from io import StringIO
from pathlib import Path
from typing import Iterable
from dotenv import load_dotenv


def sp500_ApiNinjas(api_ninja_url: String) -> list[str]:
    response = requests.get(api_ninja_url, headers={'X-Api-Key': API_NINJA})
    data = json.loads(response.text)
    fieldnames = list(data[0].keys())

    with open(SCRIPT_DIR / "Data/sp500_tickers.csv", "w", newline="") as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for row in data:
            writer.writerow(row)

    tickers = [row["ticker"] for row in data]
    return tickers

def download_csv(alpha_vantage_api_url: str) -> list[dict[str, str]]:
    with requests.Session() as s:
        download = s.get(alpha_vantage_api_url)
        decoded_content = download.content.decode('utf-8')
        cr = csv.reader(decoded_content.splitlines(), delimiter=',')
        my_list = list(cr)
    # Save the downloaded CSV to the DataIngestion_&_BronzeLayer directory
    output_path = SCRIPT_DIR / "Data/alphavantage_listing_status.csv"
    with open(output_path, "w", newline='', encoding="utf-8") as f:
        writer = csv.writer(f)
        for row in my_list:
            writer.writerow(row)
    return my_list

def format_rows(my_list: list[dict[str, str]]) -> None:
    for row in my_list:
        print(row)

def main() -> None:
    sp500_ApiNinjas(api_ninja_url)
    rows = download_csv(alpha_vantage_api_url)
    #first_elements = [row[0] for row in rows]
    #print(first_elements)
    


if __name__ == "__main__":
    SCRIPT_DIR = Path(__file__).resolve().parent
    load_dotenv(SCRIPT_DIR / ".env")
    load_dotenv()  # Fallback to project-root .env if available
    API_NINJA = os.environ.get("API_NINJA")
    ALPHA_VANTAGE_API_KEY = os.environ.get("ALPHA_VANTAGE_API_KEY")
    state = "active"
    alpha_vantage_api_url = (
            "https://www.alphavantage.co/query?function=LISTING_STATUS&state="
            f"{state}&apikey={ALPHA_VANTAGE_API_KEY}"
        )
    api_ninja_url = 'https://api.api-ninjas.com/v1/sp500'
    main()