# Mastering Snowflake: Sentiment Analysis and Performance Experiments

## Introduction
This repository hosts all the necessary resources for the Advanced Data Systems ASSG1 ``"Mastering Snowflake: Sentiment Analysis and Performance Experiments"``.

## Table of Contents
- [Introduction](#introduction)
- [Project Structure](#project-structure)
  - [Code and Data](#code-and-data)
  - [Additional Folders](#additional-folders)
- [Installation](#installation)
- [Usage](#usage)

## Project Structure

### Code and Data
- `python_udtf/naive_bayes_udtf.py`: Implementation of Naive Bayes using a UDTF in Python.
- `python_udtf/naive_bayes_udtf.sql`: Naive Bayes implementation using a UDTF in Python, adapted for Snowflake.
- `snowflake_sql/naive_bayes_sql.sql`: Naive Bayes implementation in SQL.
- `tpch_benchmark/tpch_benchmark.ipynb`: Jupyter notebook where Performance Experiments Using TPC-H are performed.
- `tpch_benchmark/query_execution_times.csv`: Query execution times for all queries across all possible combinations.
- `tpch_benchmark/average_query_execution_times.csv`: Average query execution times after three runs across all possible combinations.

**Note:** The training and test data from the Yelp Review dataset (https://huggingface.co/datasets/Yelp/yelp_review_full) were uploaded to Snowflake at the beginning of this project and are not available here on GitHub due to their size.

### Additional Folders
- `"plots"`: Directory containing images and plots used in the report.
- `"report"`: Directory containing the report of this assignment in PDF format.

## Installation
Prerequisites: Ensure Python 3.12.6 is installed on your machine. Other versions might work, but this project was developed with 3.12.6.

**1. Create and Activate a Virtual Environment**

Create a Virtual Environment in the root directory of this project by running the following commands:
  - For macOS/Linux:
      - ``python3 -m venv .venv``
      - ``source .venv/bin/activate``
  - For Windows:
      - ``python -m venv .venv``
      - ``.venv\Scripts\activate``

**2. Install Required Packages**

When the virtual environment is activated, install all necessary packages by running:
  - `pip install -r requirements.txt`

## Usage
**1. Running the TPCH Benchmark Notebook:**

To recreate the results using the ``tpch_benchmark/tpch_benchmark.ipynb`` notebook:

  - Run the whole `tpch_benchmark.ipynb` notebook, ensuring to use your own ``“user”``, ``"account"`` and ``“password”`` when connecting to Snowflake (more details inside the notebook).

**2.	Executing Naive Bayes Implementations:**

The Naive Bayes implementations, both in SQL and as a UDTF in Python, need to be executed within Snowflake.