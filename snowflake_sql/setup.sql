-- THIS FILE HAS THE SQL COMMANDS TO SETUP THE DATABASE AND WAREHOUSE AND CREATE THE TABLES NEEDED FOR THE NAIVE BAYES CLASSIFIER

-- setup of the database and warehosue
CREATE DATABASE IF NOT EXISTS COYOTE_DB;
USE DATABASE COYOTE_DB;
USE WAREHOUSE COYOTE_WH_L;

-- creating the tables
-- CREATE OR REPLACE TABLE yelp_testing(val variant);
-- CREATE OR REPLACE TABLE yelp_training(val variant);

SELECT * FROM yelp_testing;
SELECT * FROM yelp_training;

-- testing the dataset to see if everything is fine
CREATE OR REPLACE TABLE exercise_train (
    label INT,
    document string
);

CREATE OR REPLACE TABLE exercise_test (
    label INT,
    document string
);

INSERT INTO EXERCISE_TRAIN (label, document) VALUES
    (0, 'just plain boring'),
    (0, 'entirely predictable and lacks energy'),
    (0, 'no surprises and very few laughs'),
    (4, 'very powerful'),
    (4, 'the most fun film of the summer');

INSERT INTO EXERCISE_TEST (label, document) VALUES
    (0, 'predictable with no fun');

SELECT * FROM exercise_test;
SELECT * FROM exercise_train;