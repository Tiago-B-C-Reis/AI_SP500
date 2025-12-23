-- SQL for creating tables to store Alpha Vantage TIME_SERIES_INTRADAY data

-- Table to store metadata for each API call
CREATE TABLE IF NOT EXISTS s3_ingestion_logger (
    id SERIAL PRIMARY KEY,
	TS TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	function VARCHAR(50) NOT NULL,
	symbol VARCHAR(10) NOT NULL,
	path_folder_name VARCHAR(255) NOT NULL,
	object_name VARCHAR(255) NOT NULL,
	file_size_bytes INTEGER,
	log_message VARCHAR(255) NOT NULL
);

