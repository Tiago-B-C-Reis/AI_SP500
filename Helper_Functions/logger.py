import psycopg2
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

def log_to_postgres(function: str, symbol: str, path_folder_name: str, object_name: str, file_size_bytes: int, log_message: str):
    """
    Connects to the PostgreSQL database and inserts a log entry into the s3_ingestion_logger table.
    """
    conn = None
    try:
        # Connect to your postgres DB
        conn = psycopg2.connect(
            host=os.environ.get("POSTGRES_HOST", "localhost"),
            dbname=os.environ.get("POSTGRES_DB", "aisp500"),
            user=os.environ.get("POSTGRES_USER", "admin"),
            password=os.environ.get("POSTGRES_PASSWORD", "password"),
            port=os.environ.get("POSTGRES_PORT", "5432")
        )
        cur = conn.cursor()

        # SQL INSERT statement
        insert_query = """
        INSERT INTO s3_ingestion_logger (function, symbol, path_folder_name, object_name, file_size_bytes, log_message)
        VALUES (%s, %s, %s, %s, %s, %s);
        """
        
        # Data to be inserted
        record_to_insert = (function, symbol, path_folder_name, object_name, file_size_bytes, log_message)
        
        # Execute the INSERT statement
        cur.execute(insert_query, record_to_insert)

        # Commit the changes to the database
        conn.commit()

    except (Exception, psycopg2.Error) as error:
        print(f"Error while connecting to PostgreSQL or inserting data: {error}")

    finally:
        # Closing database connection.
        if conn:
            cur.close()
            conn.close()
