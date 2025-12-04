from __future__ import annotations

import argparse
import csv
import os
import time
from io import StringIO
from pathlib import Path
from typing import Iterable

import requests
from dotenv import load_dotenv

import aws_S3
from xxlimited import Str


SCRIPT_DIR = Path(__file__).resolve().parent
load_dotenv(SCRIPT_DIR / ".env")
load_dotenv()  # Fallback to project-root .env if available

def get_json_response(base_url: str, params: dict) -> dict:
    params["apikey"] = os.environ.get("ALPHA_VANTAGE_API_KEY")
    query_string = "&".join(f"{k}={v}" for k, v in params.items())
    full_url = f"{base_url}{query_string}"
    print(f"Full URL: {full_url}")

    response = requests.get(full_url)
    response.raise_for_status()  # Optional: raises error if API request fails
    time.sleep(15) # Adding a delay to respect API rate limits
    return response.json()

def load_to_s3(df_to_upload, object_name, folder_name: str = "raw"):
    """
    Loads the given DataFrame to an AWS S3 bucket using environment variables for configuration.
    """

    env_region_name = os.environ.get("REGION_NAME")
    env_bucket_name = os.environ.get("BUCKET_NAME")
    env_access_key = os.environ.get("ACCESS_KEY")
    env_secret_access_key = os.environ.get("S3_SECRET_ACCESS_KEY")

    # Check if the environment variables are set
    if (
        env_region_name is None
        or env_bucket_name is None
        or env_access_key is None
        or env_secret_access_key is None
    ):
        print(
            "Please set the environment variables: REGION_NAME, BUCKET_NAME, ACCESS_KEY, SECRET_ACCESS_KEY"
        )
    else:
        aws_S3.upload_to_s3(
            df=df_to_upload,
            s3_folder_name=folder_name,
            object_name=object_name,
            region_name=env_region_name,
            access_key=env_access_key,
            secret_access_key=env_secret_access_key,
            bucket_name=env_bucket_name,
        )
