from __future__ import annotations

import argparse
import csv
import os
import time
from . import aws_S3
from io import StringIO
from pathlib import Path
from typing import Iterable

import requests
from dotenv import load_dotenv


SCRIPT_DIR = Path(__file__).resolve().parent
dotenv_path = SCRIPT_DIR.parent / ".env"
load_dotenv(dotenv_path)


def get_json_response(base_url: str, params: dict) -> dict:
    params["apikey"] = os.environ.get("ALPHA_VANTAGE_API_KEY")
    query_string = "&".join(f"{k}={v}" for k, v in params.items())
    full_url = f"{base_url}{query_string}"
    print(f"Full URL: {full_url}")

    response = requests.get(full_url)
    response.raise_for_status()  # Optional: raises error if API request fails
    time.sleep(15) # Adding a delay to respect API rate limits
    return response.json()

def load_json_to_s3(data_to_upload: dict, object_name: str, folder_name: str) -> str:
    """
    Loads the given dictionary to an AWS S3 bucket as a JSON file using environment variables for configuration.
    Prints success or failure status.
    """

    env_region_name = os.environ.get("REGION_NAME")
    env_bucket_name = os.environ.get("BUCKET_NAME")
    env_access_key = os.environ.get("S3_ACCESS_KEY")
    env_secret_access_key = os.environ.get("S3_SECRET_ACCESS_KEY")

    # Check if the environment variables are set
    if (
        env_region_name is None
        or env_bucket_name is None
        or env_access_key is None
        or env_secret_access_key is None
    ):
        return (
            "ERROR: Please set the environment variables: REGION_NAME, BUCKET_NAME, S3_ACCESS_KEY, S3_SECRET_ACCESS_KEY"
        )
    else:
        try:
            aws_S3.upload_json_to_s3(
                data=data_to_upload,
                s3_folder_name=folder_name,
                object_name=object_name,
                region_name=env_region_name,
                access_key=env_access_key,
                secret_access_key=env_secret_access_key,
                bucket_name=env_bucket_name,
            )
            return f"SUCCESS: JSON data '{object_name}' uploaded to S3 bucket '{env_bucket_name}' in folder '{folder_name}'."
        except Exception as e:
            return f"ERROR: Failed to upload JSON data '{object_name}' to S3. Reason: {e}"


