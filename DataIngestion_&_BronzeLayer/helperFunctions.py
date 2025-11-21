from __future__ import annotations

import argparse
import csv
import os
from io import StringIO
from pathlib import Path
from typing import Iterable
from xxlimited import Str

import requests
from dotenv import load_dotenv


SCRIPT_DIR = Path(__file__).resolve().parent
load_dotenv(SCRIPT_DIR / ".env")
load_dotenv()  # Fallback to project-root .env if available

ALPHA_VANTAGE_API_KEY = os.environ.get("ALPHA_VANTAGE_API_KEY")


def defaultRequest(function: str, symbol: str, api_key: str) -> dict:
    url = (
            f"https://www.alphavantage.co/query?"
            f"function={function}"
            f"&symbol={symbol}"
            f"&apikey={api_key}"
        )
    r = requests.get(url)
    data = r.json()
    return data

def make_request(base_url: str, params: dict) -> dict:
    """
    Executes a GET request using base_url and dynamic params dict.
    """
    response = requests.get(base_url, params=params)
    response.raise_for_status()  # Optional: raises error if API request fails
    return response.json()