-- setup of the database and warehosue
CREATE DATABASE IF NOT EXISTS COYOTE_DB;
USE DATABASE COYOTE_DB;
USE WAREHOUSE COYOTE_WH_XS;

-- creating the tables
-- create or replace table yelp_testing(val variant);
-- create or replace table yelp_training(val variant);

select * from yelp_testing;
select * from yelp_training;

-- testing the dataset to see if everything is fine
create or replace table exercise_train (
    label INT,
    document string
);

create or replace table exercise_test (
    label INT,
    document string
);

insert into EXERCISE_TRAIN (label, document) VALUES
    (0, 'just plain boring'),
    (0, 'entirely predictable and lacks energy'),
    (0, 'no surprises and very few laughs'),
    (4, 'very powerful'),
    (4, 'the most fun film of the summer');

insert into EXERCISE_TEST (label, document) VALUES
    (0, 'predictable with no fun');

select * from exercise_test;
select * from exercise_train;