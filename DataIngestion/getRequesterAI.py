import csv
import json
import sys
import time
from pathlib import Path
from datetime import datetime, timedelta

# Add project root to sys.path to allow for absolute imports
sys.path.append(str(Path(__file__).resolve().parents[1]))
import Helper_Functions.ingestion as ingestion
from Helper_Functions.logger import log_to_postgres


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
    api_urls_path = Path(__file__).parent / "Data" / "alpha_intelligence.json"
    with open(api_urls_path, encoding='utf-8') as jsonfile:
        return json.load(jsonfile)

def analytics_fixed_window(base_url: str, params: dict, sleep_time: int) -> dict:
    calculation_groups = [
            "MIN,MAX,MEAN",
            "MEDIAN,CUMULATIVE_RETURN,MAX_DRAWDOWN",
            "VARIANCE(annualized=True),STDDEV(annualized=True),HISTOGRAM(bins=10)"
        ]
    sp500_tickers = get_sp500_tickers()
    for ticker in sp500_tickers:
        combined_data = {}
        for calcs in calculation_groups:
            params['CALCULATIONS'] = calcs
            # Make the request
            response = ingestion.get_json_response(base_url, params, sleep_time=sleep_time)
            if 'payload' in response:
                for sym, values in response['payload'].items():
                    combined_data.setdefault(sym, {}).update(values)
    return combined_data


def load_and_log_json(response: dict, params: dict, symbol: str, path_folder_name: str, object_name: str) -> None:
    try:
        # Extract the json file size in bytes
        file_size_bytes = len(json.dumps(response, indent=4).encode('utf-8'))
        # Load the json file to S3
        s3_upload_message = ingestion.load_json_to_s3(response, object_name, path_folder_name)

        # Log the successful ingestion
        log_to_postgres(
            function=params.get('function'),
            symbol=symbol,
            path_folder_name=path_folder_name,
            object_name=object_name,
            file_size_bytes=file_size_bytes,
            log_message=s3_upload_message
        )
    except Exception as e:
        print(f"An error occurred for symbol {symbol}: {e}")
        log_to_postgres(
            function=params.get('function'),
            symbol=symbol,
            path_folder_name=path_folder_name,
            object_name=object_name,
            file_size_bytes=0,
            log_message=s3_upload_message + " - " + str(e)
        )

sp500_tickers = get_sp500_tickers()
data = get_api_urls()


if __name__ == "__main__":
    # Iterate over each API endpoint and make requests for each ticker
    for category_name, endpoints in data.items():
        for endpoint in endpoints:
            base_url = endpoint["base_url"]
            params = endpoint["params"].copy()
            # Get the year and week number as a string (e.g., "2024_W02")
            today = datetime.date.today()
            iso_year_week = f"{today.year}_W{today.strftime('%V')}"
            path_folder_name = "raw/" + category_name + "/" + params.get('function') + "/" + iso_year_week

            for symbol in sp500_tickers:
                object_name = f"{params.get('function')}_{symbol}_{time.strftime('%Y%m%d%H%M%S')}.json"
                print(f"{path_folder_name} - Calling → {params.get('function')} for {symbol}, Object Name: {object_name}")

                if params.get('function') == "EARNINGS_CALL_TRANSCRIPT":
                    params["symbol"] = symbol
                    for quarter in 
                        params["quarter"] = quarter
                        earnings_get_json = ingestion.get_json_response(base_url, params, sleep_time=15)
                        load_and_log_json(earnings_get_json, params, symbol, path_folder_name, object_name)
                elif params.get('function') == "INSIDER_TRANSACTIONS":
                    params["symbol"] = symbol
                    insider_get_json = ingestion.get_json_response(base_url, params, sleep_time=15)
                    load_and_log_json(insider_get_json, params, symbol, path_folder_name, object_name)
                elif params.get('function') == "ANALYTICS_FIXED_WINDOW":
                    analytics_get_json = analytics_fixed_window(base_url, params, sleep_time=15)
                    load_and_log_json(analytics_get_json, params, symbol, path_folder_name, object_name)