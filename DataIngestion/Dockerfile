# Use an official Python runtime as a parent image
FROM python:3.13-slim

# Set the working directory to /app
WORKDIR /app

# Install poetry
RUN pip install poetry

# Copy the project dependency files from the root context
# This assumes the build command is run from the project root:
# docker build -f DataIngestion/Dockerfile .
COPY pyproject.toml poetry.lock ./

# Install dependencies
# --no-root: Do not install the project itself, just the dependencies
RUN poetry config virtualenvs.create false \
    && poetry install --no-interaction --no-ansi --no-root

# Copy the DataIngestion code into /app
COPY DataIngestion/ ./

# Set the default command to run the collector script
CMD ["python", "getRequester.py"]
