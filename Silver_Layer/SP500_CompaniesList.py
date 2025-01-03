import os
import logging
from dotenv import load_dotenv
from pyspark.sql import SparkSession
from pyspark.sql.dataframe import DataFrame

# Initialize a Spark session
spark = (SparkSession.builder
         .appName("Read CSV from S3")
         .config("spark.jars.packages", "org.apache.hadoop:hadoop-aws:3.3.2")
         .config("spark.driver.bindAddress", "127.0.0.1")  # Bind to localhost
         .config("spark.driver.host", "127.0.0.1")  # Set host explicitly
         .getOrCreate())


def read_csv_from_s3(bucket_name: str, access_key: str, secret_access_key: str) -> DataFrame:
    """
    Reads a CSV file from an S3 bucket using PySpark.
    """
    # Set AWS credentials
    hadoop_conf = spark._jsc.hadoopConfiguration()
    hadoop_conf.set("fs.s3a.access.key", access_key)
    hadoop_conf.set("fs.s3a.secret.key", secret_access_key)
    hadoop_conf.set("fs.s3a.endpoint", "s3.amazonaws.com")

    # Specify the S3 bucket and file path
    file_path = "SP500_Companies_List/SP500_Companies_2024-12-30 16:27:56.csv"
    s3_path = f"s3a://{bucket_name}/{file_path}"

    # Read the CSV file into a PySpark DataFrame
    df = spark.read.csv(
        s3_path,
        header=True,
        inferSchema=True
    )

    # Return the DataFrame content
    return df


if __name__ == "__main__":

    # Load the environment variables from the .env file in Data_Sources
    load_dotenv(dotenv_path="/Users/tiagoreis/PycharmProjects/AI_SP500/DataIngestion_&_BronzeLayer/.env")

    # Load the environment variables
    env_region_name = os.getenv("REGION_NAME")
    env_bucket_name = os.getenv("BUCKET_NAME")
    env_access_key = os.getenv("ACCESS_KEY")
    env_secret_access_key = os.getenv("SECRET_ACCESS_KEY")

    # Check for missing environment variables
    if not all([env_bucket_name, env_access_key, env_secret_access_key]):
        logging.error("Environment variables are missing. Check the .env file.")
        exit(1)

    try:
        df = read_csv_from_s3(env_bucket_name, env_access_key, env_secret_access_key)
        logging.info("CSV file loaded successfully!")
        df.show()
    except Exception as e:
        logging.error(f"Error reading CSV from S3: {e}")

