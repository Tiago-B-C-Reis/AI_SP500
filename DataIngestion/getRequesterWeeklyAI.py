import csv
import json
import sys
import time
from pathlib import Path
import datetime

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

def read_json(file_name: str) -> dict:
    """Reads a JSON file."""
    api_urls_path = Path(__file__).parent / "Data" / file_name
    with open(api_urls_path, encoding='utf-8') as jsonfile:
        return json.load(jsonfile)

def mark_data_as_processed(file_name: str, time: str, json_entry: str) -> None:
    """
    Adds a quarter to the 'quarters_processed' list in a JSON file.
    Creates the file if it doesn't exist.
    """
    # Define the path (adjust "Data" folder as needed per your project structure)
    file_path = Path(__file__).parent / "Data" / file_name
    
    # 1. Load existing data or create default structure
    if file_path.exists():
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except json.JSONDecodeError:
            # Handle empty or corrupted files
            data = {json_entry: []}
    else:
        data = {json_entry: []}

    # 2. Add quarter if not already present
    if time not in data[json_entry]:
        data[json_entry].append(time)
        
        # Optional: Sort the list so the file stays organized
        data[json_entry].sort()

        # 3. Write back to file
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=4)
            
        print(f"Updated {file_name}: Added {time}")
    else:
        print(f"Skipped: {time} is already in {file_name}")

def get_quarters_since(start_year):
    today = datetime.date.today()
    current_year = today.year
    # Calculate current quarter (1-4)
    current_quarter = (today.month - 1) // 3 + 1
    
    quarters_list = []
    
    for year in range(start_year, current_year + 1):
        # If it's the current year, stop at the current quarter. 
        # Otherwise, process all 4 quarters.
        end_q = current_quarter if year == current_year else 4
        
        for q in range(1, end_q + 1):
            quarters_list.append(f"{year}Q{q}")
            
    return quarters_list

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



# --- MAIN EXECUTION ---
if __name__ == "__main__":
    sp500_tickers = get_sp500_tickers()
    data = read_json("alpha_intelligence.json")
    # We read this once at start, but we will also re-read or update locally to stay in sync
    processed_data = read_json("year_quarter_List.json")

    for category_name, endpoints in data.items():
        for endpoint in endpoints:
            base_url = endpoint["base_url"]
            params = endpoint["params"].copy()
            function_name = params.get('function')
            
            # Common path setup
            today = datetime.date.today()
            iso_year_week = f"{today.year}_W{today.strftime('%V')}"
            path_folder_name = f"raw/{category_name}/{function_name}/{iso_year_week}"

            print(f"--- Starting endpoint: {function_name} ---")

            # ---------------------------------------------------------------------------------
            # CASE 1: EARNINGS (Iterate Quarter -> Then Symbol)
            # ---------------------------------------------------------------------------------
            if function_name == "EARNINGS_CALL_TRANSCRIPT":
                # Generate full list of quarters since 2020
                all_quarters = get_quarters_since(2020)
                
                for quarter in all_quarters:
                    # Check if quarter is already done
                    if quarter in processed_data["quarters_processed"]:
                        print(f"Skipping {quarter} (Already Processed)")
                        continue

                    print(f"Processing Quarter: {quarter}")
                    
                    # Process ALL symbols for this quarter
                    for symbol in sp500_tickers:
                        params["symbol"] = symbol
                        params["quarter"] = quarter
                        
                        # Added quarter to object name for uniqueness
                        object_name = f"{function_name}_{symbol}_{quarter}_{time.strftime('%Y%m%d%H%M%S')}.json"
                        print(f"Calling {function_name} for {symbol} ({quarter})")

                        earnings_get_json = ingestion.get_json_response(base_url, params, sleep_time=15)
                        load_and_log_json(earnings_get_json, params, symbol, path_folder_name, object_name)

                    # CRITICAL: Only mark as processed after ALL symbols loop finishes successfully
                    mark_data_as_processed("year_quarter_List.json", quarter, "quarters_processed")
                    # Update local list so we don't process it again if loops are weird
                    processed_data["quarters_processed"].append(quarter)

            # ---------------------------------------------------------------------------------
            # CASE 2: DEFAULT CASE (INSIDER_TRANSACTIONS AND EARNINGS_CALL_TRANSCRIPT)
            # ---------------------------------------------------------------------------------
            else:
                if iso_year_week not in processed_data["year_week_list"]:
                    for symbol in sp500_tickers:
                        params["symbol"] = symbol
                        object_name = f"{function_name}_{symbol}_{time.strftime('%Y%m%d%H%M%S')}.json"
                        print(f"Calling {function_name} for {symbol}")
                        if function_name == "INSIDER_TRANSACTIONS":
                            api_response = ingestion.get_json_response(base_url, params, sleep_time=15)
                            load_and_log_json(api_response, params, symbol, path_folder_name, object_name)
                        elif function_name == "EARNINGS_CALL_TRANSCRIPT":
                            api_response = analytics_fixed_window(base_url, params, sleep_time=15)
                            load_and_log_json(api_response, params, symbol, path_folder_name, object_name)
                    # CRITICAL: Only mark as processed after ALL symbols loop finishes successfully
                    mark_data_as_processed("year_quarter_List.json", iso_year_week, "year_week_list")
                    # Update local list so we don't process it again if loops are weird
                    processed_data["year_week_list"].append(iso_year_week)
                else:
                    print(f"Skipping {iso_year_week} (Already Processed)")