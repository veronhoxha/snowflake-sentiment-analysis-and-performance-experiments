-- setup of the database and warehosue
CREATE DATABASE IF NOT EXISTS COYOTE_DB;
USE DATABASE COYOTE_DB;
USE WAREHOUSE COYOTE_WH_L;

-- dropping up any existing table and view to start fresh
DROP TABLE IF EXISTS stopwords;
DROP TABLE IF EXISTS training_data;
DROP TABLE IF EXISTS training_words;
DROP TABLE IF EXISTS training_words_binary;
DROP TABLE IF EXISTS word_frequencies;
DROP VIEW IF EXISTS total_words_per_label;
DROP VIEW IF EXISTS prior_probabilities;
DROP VIEW IF EXISTS label_word_combinations;
DROP TABLE IF EXISTS conditional_probabilities;
DROP TABLE IF EXISTS test_data;
DROP TABLE IF EXISTS test_words;
DROP TABLE IF EXISTS test_words_binary;
DROP TABLE IF EXISTS test_log_probs;
DROP TABLE IF EXISTS test_total_log_probs;
DROP VIEW IF EXISTS final_predictions;
DROP VIEW IF EXISTS precision_per_label;

-- creating a table for storing stopwords
CREATE OR REPLACE TABLE stopwords(word STRING);

-- inserting some random picked stopwords
INSERT INTO stopwords(word) VALUES
('the'), ('and'), ('is'), ('in'), ('at'), ('of'), ('a'), ('to'), ('it'), ('for'),
('on'), ('with'), ('this'), ('that'), ('an'), ('as'), ('are'), ('was'), ('but'),
('be'), ('by'), ('not'), ('or'), ('from'), ('so'), ('if'), ('they'), ('you'),
('we'), ('he'), ('she'), ('her'), ('his'), ('them'), ('their'), ('our'), ('i'),
('me'), ('my'), ('your'), ('yours'), ('ours'), ('ourselves'), ('yourselves');

-- clean_text function to remove stopwords and perform stemming (I remeber that removing stopwords was not needed but I was experimenting around)
CREATE OR REPLACE FUNCTION clean_text("input_text" STRING)
RETURNS ARRAY
LANGUAGE JAVASCRIPT
STRICT IMMUTABLE
AS
$$
    if (input_text === null) return [];
    
    // removing special characters and converting to lowercase
    let cleaned = input_text.replace(/[^a-zA-Z0-9 ,.?!\s]/g, ' ').toLowerCase();
    
    // splitting into words
    let words = cleaned.split(/\s+/);
    
    // list of stopwords just so kinda random ones picked
    let stopwords = new Set([
        'the', 'and', 'is', 'in', 'at', 'of', 'a', 'to', 'it', 'for',
        'on', 'with', 'this', 'that', 'an', 'as', 'are', 'was', 'but',
        'be', 'by', 'not', 'or', 'from', 'so', 'if', 'they', 'you',
        'we', 'he', 'she', 'her', 'his', 'them', 'their', 'our',
        'i', 'me', 'my', 'your', 'yours', 'ours', 'ourselves', 'yourselves'
    ]);
    
    // stemming function
    function stem(word) {
        return word.replace(/(ing|ed|ly|es|s)$/,'');
    }
    
    // removing stopwords and perform stemming
    let processed = words.filter(word => !stopwords.has(word) && word.length > 0)
                         .map(word => stem(word));
    return processed;
$$;

-- preparing training data with binary labels
CREATE OR REPLACE TABLE training_data AS
SELECT
    ROW_NUMBER() OVER (ORDER BY NULL) AS doc_id,
    CASE 
        WHEN val:"label"::INT IN (0) THEN 0  -- negative sentiment (label 0 stands for 1 stars the lowest possible)
        WHEN val:"label"::INT IN (4) THEN 1  -- positive sentiment (label 4 stands for 5 stars given the highest one possible)
    END AS label,
    clean_text(val:"text") AS words_array
FROM yelp_training
WHERE val:"text" IS NOT NULL AND val:"label"::INT IN (0, 4);

-- tokenizing training data and clipping counts at 1 using the distinct keyword
CREATE OR REPLACE TABLE training_words_binary AS
SELECT DISTINCT
    doc_id,
    label,
    s.VALUE::STRING AS word
FROM training_data,
    LATERAL FLATTEN(input => words_array) AS s
WHERE s.VALUE IS NOT NULL
    AND s.VALUE <> '';

-- calculating word frequencies per label
CREATE OR REPLACE TABLE word_frequencies AS
SELECT
    label,
    word,
    COUNT(*) AS word_count
FROM training_words_binary
GROUP BY label, word;

-- calculating total words per label
CREATE OR REPLACE VIEW total_words_per_label AS
SELECT
    label,
    SUM(word_count) AS total_word_count
FROM word_frequencies
GROUP BY label;

-- calculating vocabulary size
SET vocab_size = (SELECT COUNT(DISTINCT word) FROM training_words_binary);

-- calculate prior probabilities
SET total_docs = (SELECT COUNT(*) FROM training_data);

CREATE OR REPLACE VIEW prior_probabilities AS
SELECT
    label,
    COUNT(*) AS doc_count,
    (COUNT(*) * 1.0) / $total_docs AS prior_prob
FROM training_data
GROUP BY label;

-- creating label-word combinations
CREATE OR REPLACE VIEW label_word_combinations AS
SELECT
    l.label,
    w.word
FROM (SELECT DISTINCT label FROM training_words_binary) AS l
CROSS JOIN (SELECT DISTINCT word FROM training_words_binary) AS w;

-- calculating conditional probabilities for each label-word combination
CREATE OR REPLACE TABLE conditional_probabilities AS
SELECT
    lwc.label,
    lwc.word,
    (COALESCE(wf.word_count, 0) + 1.0) / (twpl.total_word_count + $vocab_size) AS conditional_prob
FROM label_word_combinations AS lwc
LEFT JOIN word_frequencies AS wf
    ON lwc.label = wf.label AND lwc.word = wf.word
JOIN total_words_per_label AS twpl
    ON lwc.label = twpl.label;

-- preparing test data with binary labels
CREATE OR REPLACE TABLE test_data AS
SELECT
    ROW_NUMBER() OVER (ORDER BY NULL) AS doc_id,
    CASE 
        WHEN val:"label"::INT IN (0) THEN 0  -- negative sentiment (label 0 stands for 1 stars the lowest possible)
        WHEN val:"label"::INT IN (4) THEN 1  -- positive sentiment (label 4 stands for 5 stars given the highest one possible)
    END AS true_label,
    clean_text(val:"text") AS words_array
FROM yelp_testing
WHERE val:"text" IS NOT NULL AND val:"label"::INT IN (0, 4);

-- tokenizing test data and clipping counts at 1 using the distinct keyword
CREATE OR REPLACE TABLE test_words_binary AS
SELECT DISTINCT
    doc_id,
    true_label,
    s.VALUE::STRING AS word
FROM test_data,
    LATERAL FLATTEN(input => words_array) AS s
WHERE s.VALUE IS NOT NULL
    AND s.VALUE <> '';

-- removing words not seen in training to prevent null probabilities
DELETE FROM test_words_binary
WHERE word NOT IN (SELECT DISTINCT word FROM training_words_binary);

-- defining a minimum probability to prevent log(0)
SET min_prob = 1e-10;

-- calculating log probabilities for each label
CREATE OR REPLACE TABLE test_log_probs AS
SELECT
    tw.doc_id,
    l.label,
    SUM(LN(GREATEST(
        COALESCE(cp.conditional_prob, 1.0 / (twpl.total_word_count + $vocab_size)),
        $min_prob
    ))) AS sum_log_cond_prob
FROM test_words_binary AS tw
JOIN (SELECT DISTINCT label FROM prior_probabilities) AS l
LEFT JOIN conditional_probabilities AS cp
    ON tw.word = cp.word AND l.label = cp.label
JOIN total_words_per_label AS twpl
    ON l.label = twpl.label
GROUP BY tw.doc_id, l.label;

-- adding prior probabilities
CREATE OR REPLACE TABLE test_total_log_probs AS
SELECT
    tlp.doc_id,
    tlp.label,
    (SELECT LN(prior_prob) FROM prior_probabilities WHERE label = tlp.label) + tlp.sum_log_cond_prob AS total_log_prob
FROM test_log_probs AS tlp;

-- predicting labels
CREATE OR REPLACE VIEW final_predictions AS
SELECT
    ranked.doc_id,
    td.true_label,
    ranked.label AS predicted_label
FROM (
    SELECT
        doc_id,
        label,
        total_log_prob,
        ROW_NUMBER() OVER (PARTITION BY doc_id ORDER BY total_log_prob DESC) AS rank
    FROM test_total_log_probs
) AS ranked
JOIN test_data td ON ranked.doc_id = td.doc_id
WHERE rank = 1;

-- precision per label
CREATE OR REPLACE VIEW precision_per_label AS
SELECT
    predicted_label AS label,
    SUM(CASE WHEN predicted_label = true_label THEN 1 ELSE 0 END) AS true_positives,
    SUM(CASE WHEN predicted_label <> true_label THEN 1 ELSE 0 END) AS false_positives,
    (SUM(CASE WHEN predicted_label = true_label THEN 1 ELSE 0 END) * 100.0) /
    NULLIF(SUM(CASE WHEN predicted_label = true_label THEN 1 ELSE 0 END) + SUM(CASE WHEN predicted_label <> true_label THEN 1 ELSE 0 END), 0) AS precision_percentage
FROM final_predictions
GROUP BY predicted_label
ORDER BY precision_percentage DESC;

-- precision per label
-- SELECT * FROM precision_per_label;

-- calculating overall precision
SELECT
    (SUM(true_positives) * 100.0) / NULLIF(SUM(true_positives + false_positives), 0) AS overall_precision_percentage
FROM precision_per_label;