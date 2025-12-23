import boto3
import time
import calendar
import datetime
import pandas as pd
from io import StringIO
import json


# This function will load the data from the S3 bucket
def upload_to_s3(df: pd.DataFrame,
                 bucket_name: str,
                 s3_folder_name: str,
                 object_name: str,
                 region_name: str,
                 access_key: str,
                 secret_access_key: str) -> bool:
    """
    Uploads a DataFrame to S3 as a CSV file.
    """
    # Convert the DataFrame to CSV in memory
    csv_buffer = StringIO()
    df.to_csv(csv_buffer, index=False)

    # Initialize S3 client
    s3_client = boto3.client(
        "s3",
        region_name=region_name,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_access_key,
    )

    # Get the current UTC time (TimeStamp)
    utc_time_tuple = time.gmtime()
    utc_timestamp = calendar.timegm(utc_time_tuple)
    datetime_object = datetime.datetime.fromtimestamp(utc_timestamp)
    formatted_datetime = datetime_object.strftime("%Y-%m-%d %H:%M:%S")

    # Append the formatted datetime to the file name
    file_name = f"{object_name}_{formatted_datetime}"

    # Upload the CSV file to the specified bucket
    try:
        response = s3_client.put_object(Bucket=bucket_name,
                                        Key=f"{s3_folder_name}/{file_name}.csv",
                                        Body=csv_buffer.getvalue()
                                        )
        print(f'Successfully uploaded {file_name}.csv to {bucket_name}/{s3_folder_name}/{file_name}.csv')
    except Exception as e:
        print(f"Error uploading file: {e}")
        return False

    return True


def upload_json_to_s3(data: dict,
                      bucket_name: str,
                      s3_folder_name: str,
                      object_name: str,
                      region_name: str,
                      access_key: str,
                      secret_access_key: str) -> bool:
    """
    Uploads a dictionary to S3 as a JSON file.
    """
    # Convert the dictionary to a JSON string in memory
    json_buffer = json.dumps(data, indent=4)
    file_size_bytes = len(json_buffer.encode('utf-8'))

    # Initialize S3 client
    s3_client = boto3.client(
        "s3",
        region_name=region_name,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_access_key,
    )

    # Upload the JSON file to the specified bucket
    try:
        key = f"{s3_folder_name}/{object_name}"
        response = s3_client.put_object(Bucket=bucket_name,
                                        Key=key,
                                        Body=json_buffer
                                        )
        print(f'Successfully uploaded {object_name} ({file_size_bytes} bytes) to {bucket_name}/{key}')
    except Exception as e:
        print(f"Error uploading file: {e}")
        return False

    return True


# This function will load the data from the S3 bucket
def read_from_s3(bucket_name: str,
                 s3_folder_name: str,
                 region_name: str,
                 access_key: str,
                 secret_access_key: str) -> pd.DataFrame:
    """
    Reads the most recent CSV file from S3 and returns a pandas DataFrame.
    """

    # Initialize S3 client
    s3_client = boto3.client(
        "s3",
        region_name=region_name,
        aws_access_key_id=access_key,
        aws_secret_access_key=secret_access_key,
    )

    try:
        # List objects in the folder within the bucket
        response = s3_client.list_objects_v2(
            Bucket=bucket_name,
            Prefix=s3_folder_name
        )

        # Initialize variables to track the most recent file
        most_recent_file = None
        last_modified_time = None

        # Loop through the objects to find the most recent file
        for obj in response.get('Contents', []):
            if most_recent_file is None or obj['LastModified'] > last_modified_time:
                most_recent_file = obj['Key']
                last_modified_time = obj['LastModified']

        if not most_recent_file:
            print("No files found in the specified folder.")
            return None

        print(f"Most recent file: {most_recent_file}")

        # Fetch the most recent file from S3
        response = s3_client.get_object(Bucket=bucket_name, Key=most_recent_file)

        # Check the content type (optional)
        file_content_type = response['ContentType']
        if 'csv' not in file_content_type:
            print(f"File is not a CSV: {most_recent_file} - ContentType: {file_content_type}")
            return None

        # Read the CSV data from the response
        csv_data = response['Body'].read()
        print(f"Raw data: {csv_data[:100]}")  # Print the first 100 bytes of raw data for debugging

        # Decode the data only if it's in the expected format
        csv_data = csv_data.decode('utf-8')

        # Use StringIO to load the CSV data into a pandas DataFrame
        df = pd.read_csv(StringIO(csv_data))
        print(f"Successfully read {most_recent_file}")
    except Exception as e:
        print(f"Error reading file: {e}")
        return None

    return df