import os
import requests
import pandas as pd
from bs4 import BeautifulSoup
from dotenv import load_dotenv
from Helper_Functions import aws_S3


def SP500_ListCollector(url: str) -> pd.DataFrame:
    # Make a GET request
    response = requests.get(url)

    # Check the response status
    if response.status_code == 200:
        # Parse the content with BeautifulSoup
        soup = BeautifulSoup(response.content, 'html.parser')

        # Initialize lists to store table data
        symbols = []
        company_names = []
        market_caps = []
        stock_prices = []
        percent_changes = []
        revenues = []

        # Find all rows containing stock data
        rows = soup.find_all('tr', class_='svelte-utsffj')

        for row in rows[1:]:  # Skip the first row (header)
            try:
                # Extract columns from the row
                symbol = row.find('a').text.strip()
                company_name = row.find_all('td', class_='slw svelte-utsffj')[0].text.strip()
                market_cap = row.find_all('td', class_='svelte-utsffj')[1].text.strip()
                stock_price = row.find_all('td', class_='svelte-utsffj')[2].text.strip()
                # Handle both positive and negative %Change values
                percent_change_element = row.find('td', class_='rg svelte-utsffj') or row.find('td',
                                                                                               class_='rr svelte-utsffj')
                percent_change = percent_change_element.text.strip() if percent_change_element else None
                revenue = row.find_all('td', class_='tr svelte-utsffj')[0].text.strip()

                # Append data to the lists
                symbols.append(symbol)
                company_names.append(company_name)
                market_caps.append(market_cap)
                stock_prices.append(stock_price)
                percent_changes.append(percent_change)
                revenues.append(revenue)
            except Exception as e:
                # Skip rows that don't match the expected structure
                print(f"this row was skipped due to an error: {e}, {row}")
                raise e

        # Create a DataFrame from the data
        data = {
            'Symbol': symbols,
            'Company Name': company_names,
            'Market Cap': market_caps,
            'Stock Price': stock_prices,
            '%Change': percent_changes,
            'Revenue': revenues
        }
        df = pd.DataFrame(data)

        if df.empty is False:
            return df
        else:
            raise ValueError("Dataframe is empty")
    else:
        print(f"Failed to retrieve data. HTTP Status code: {response.status_code}")


if __name__ == "__main__":

    # Load the environment variables from the .env file in Data_Sources
    load_dotenv()

    # URL to scrape
    url = 'https://stockanalysis.com/list/sp-500-stocks/'

    # Call the function to load the data into the dataframes
    df_to_upload = SP500_ListCollector(url)

    # Load the environment variables
    env_region_name = os.getenv("REGION_NAME")
    env_bucket_name = os.getenv("BUCKET_NAME")
    env_access_key = os.getenv("ACCESS_KEY")
    env_secret_access_key = os.getenv("SECRET_ACCESS_KEY")

    # Check if the environment variables are set
    if env_region_name is None or env_bucket_name is None or env_access_key is None or env_secret_access_key is None:
        print("Please set the environment variables: REGION_NAME, BUCKET_NAME, ACCESS_KEY, SECRET_ACCESS_KEY")
    else:
        aws_S3.upload_to_s3(df=df_to_upload
                            , s3_folder_name="SP500_Companies_List"
                            , object_name="SP500_Companies"
                            , region_name=env_region_name
                            , access_key=env_access_key
                            , secret_access_key=env_secret_access_key
                            , bucket_name=env_bucket_name
                            )
