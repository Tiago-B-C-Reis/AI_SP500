import json
import sys
import time
from pathlib import Path
from datetime import datetime, timedelta

# Add project root to sys.path to allow for absolute imports
sys.path.append(str(Path(__file__).resolve().parents[1]))
import Helper_Functions.ingestion as ingestion
from Helper_Functions.logger import log_to_postgres


def get_api_urls() -> dict:
    """Reads API URLs from a JSON file."""
    api_urls_path = Path(__file__).parent / "Data" / "alpha_intelligence_daily.json"
    with open(api_urls_path, encoding='utf-8') as jsonfile:
        return json.load(jsonfile)

data = get_api_urls()


if __name__ == "__main__":
    while True:
        print(f"Starting daily ingestion at {datetime.now()}")
        # Iterate over each API endpoint and make requests for each ticker
        for category_name, endpoints in data.items():
            for endpoint in endpoints:
                base_url = endpoint["base_url"]
                params = endpoint["params"].copy()
                # Get the year and week number as a string (e.g., "2024_W02")
                today = datetime.date.today()
                iso_year_week = f"{today.year}_W{today.strftime('%V')}"
                path_folder_name = "raw/" + category_name + "/" + params.get('function') + "/" + iso_year_week
                object_name = f"{params.get('function')}_{time.strftime('%Y%m%d%H%M%S')}.json"

                print(f"{path_folder_name} - Calling → {params.get('function')}, Object Name: {object_name}")
                try:
                    # Make the request
                    if params.get('function') == "NEWS_SENTIMENT":
                        params["time_from"] = (datetime.now() - timedelta(days=1)).strftime('%Y%m%dT%H%M')
                    response = ingestion.get_json_response(base_url, params, sleep_time=0)
                    # Extract the json file size in bytes
                    file_size_bytes = len(json.dumps(response, indent=4).encode('utf-8'))
                    # Load the json file to S3
                    s3_upload_message = ingestion.load_json_to_s3(response, object_name, path_folder_name)

                    # Log the successful ingestion
                    log_to_postgres(
                        function=params.get('function'),
                        symbol="N/A",
                        path_folder_name=path_folder_name,
                        object_name=object_name,
                        file_size_bytes=file_size_bytes,
                        log_message=s3_upload_message
                    )
                except Exception as e:
                    print(f"An error occurred for function {params.get('function')}: {e}")
                    log_to_postgres(
                        function=params.get('function'),
                        symbol="N/A",
                        path_folder_name=path_folder_name,
                        object_name=object_name,
                        file_size_bytes=0,
                        log_message=s3_upload_message + " - " + str(e)
                    )
        
        print("Daily ingestion complete. Sleeping for 24 hours...")
        time.sleep(86400)