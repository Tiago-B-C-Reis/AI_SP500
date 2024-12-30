from pyspark.sql import SparkSession
from pyspark.sql.functions import col
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, DoubleType, TimestampType
from dotenv import load_dotenv
from Helper_Functions import aws_S3
from io import StringIO
import boto3
import subprocess
import logging
import pandas as pd
import os



# Create SparkSession
spark = SparkSession.builder \
    .config("spark.jars", "/Users/tiagoreis/PycharmProjects/AI_SP500/PostgreSQL/postgresql-42.7.3.jar") \
    .master("local") \
    .appName("SilverLayer_Transformations") \
    .getOrCreate()

# Load the environment variables from the .env file in Data_Sources
load_dotenv()

# Load the environment variables
env_region_name = os.getenv("REGION_NAME")
env_bucket_name = os.getenv("BUCKET_NAME")
env_access_key = os.getenv("ACCESS_KEY")
env_secret_access_key = os.getenv("SECRET_ACCESS_KEY")

# Initialize S3 client
s3_client = boto3.client(
    "s3",
    region_name=env_region_name,
    aws_access_key_id=env_access_key,
    aws_secret_access_key=env_secret_access_key,
)

# Store contents of bucket
objects_list = s3_client.list_objects_v2(Bucket=env_bucket_name).get("Contents")

# Iterate over every object in bucket
for obj in objects_list:
    #  Store object name
    obj_name = obj["Key"]
    # Read an object from the bucket
    response = s3_client.get_object(Bucket=env_bucket_name, Key=obj_name)
    # Read the object’s content as text
    object_content = response["Body"].read().decode("utf-8")
    # Print all the contents
    print(f"Contents of {obj_name}\n--------------")
    print(object_content, end="\n\n")
