CREATE DATABASE IF NOT EXISTS COYOTE_DB;
USE DATABASE COYOTE_DB;
USE WAREHOUSE COYOTE_WH_L;

-- combining training and testing data into one table because 
-- the only way to pass both your training and testing data into a UDTF is to combine them in the query that calls the UDTF. 

DROP TABLE IF EXISTS training_or_testing;

CREATE OR REPLACE TABLE training_or_testing AS
SELECT TRUE AS training_data, 
       CASE 
           WHEN val:"label"::INT = (0) THEN 0  -- negative sentiment (label 0 stands for 1 stars the lowest possible)
           WHEN val:"label"::INT = (4) THEN 1  -- positive sentiment (label 4 stands for 5 stars given the highest one possible)
       END AS label,
       val:"text"::STRING AS text
FROM yelp_training
WHERE val:"text" IS NOT NULL AND val:"label"::INT IN (0, 4)

UNION ALL

SELECT FALSE AS training_data, 
       CASE 
           WHEN val:"label"::INT = (0) THEN 0  -- negative sentiment (label 0 stands for 1 stars the lowest possible)
           WHEN val:"label"::INT = (4) THEN 1  -- positive sentiment (label 4 stands for 5 stars given the highest one possible)
       END AS label,
       val:"text"::STRING AS text
FROM yelp_testing
WHERE val:"text" IS NOT NULL AND val:"label"::INT IN (0, 4);


-- In UDTF implementation

CREATE OR REPLACE FUNCTION sentiment_analysis_udtf(training_data BOOLEAN, label INT, text STRING)
RETURNS TABLE (text STRING, true_label INT, predicted_label INT)
LANGUAGE PYTHON
RUNTIME_VERSION=3.10
HANDLER='COYOTESentimentAnalysisUDTF'
AS
$$
import re
import math
from collections import defaultdict

def clean_text(input_text):

    if input_text is None:
        return []

    # removing special characters and converting to lowercase

    cleaned = re.sub(r'[^a-zA-Z0-9 ,.?!\s]', ' ', input_text).lower()

    # splitting into words
    words = re.split(r'\s+', cleaned)

    # list of stopwords just so kinda random ones picked
    stopwords = set([
        'the', 'and', 'is', 'in', 'at', 'of', 'a', 'to', 'it', 'for',
        'on', 'with', 'this', 'that', 'an', 'as', 'are', 'was', 'but',
        'be', 'by', 'not', 'or', 'from', 'so', 'if', 'they', 'you',
        'we', 'he', 'she', 'her', 'his', 'them', 'their', 'our',
        'i', 'me', 'my', 'your', 'yours', 'ours', 'ourselves', 'yourselves'
    ])

    # stemming function
    def stem(word):
        return re.sub(r'(ing|ed|ly|es|s)$', '', word)

    # removing stopwords and perform stemming
    processed = [stem(word) for word in words if word not in stopwords and len(word) > 0]

    return processed

class COYOTESentimentAnalysisUDTF:
   
    def train_model(self, data):

        doc_count_per_label = defaultdict(int)
        word_freq_per_label = defaultdict(lambda: defaultdict(int))
        total_documents = len(data)
        vocabulary = set()

        for label, text in data:
            doc_count_per_label[label] += 1
            words = clean_text(text)
            unique_words = set(words) 
            for word in unique_words:
                word_freq_per_label[label][word] += 1 
                vocabulary.add(word)

        # calculating prior probabilities (log scale)
        prior_log_probabilities = {
            label: math.log(count / total_documents)
            for label, count in doc_count_per_label.items()
        }

        # calculating total words per label
        total_words_per_label = {
            label: sum(word_freq_per_label[label].values())
            for label in doc_count_per_label
        }

        # vocab size
        vocab_size = len(vocabulary)

        # calculating conditional probabilities (log scale)
        conditional_log_probabilities = {}
        for label in doc_count_per_label:
            conditional_log_probabilities[label] = {}
            total_word_count = total_words_per_label[label]
            for word in vocabulary:
                word_count = word_freq_per_label[label].get(word, 0)
                probability = (word_count + 1.0) / (total_word_count + vocab_size)
                conditional_log_probabilities[label][word] = math.log(probability)

        return {
            'prior_log_probabilities': prior_log_probabilities,
            'conditional_log_probabilities': conditional_log_probabilities,
            'vocabulary': vocabulary,
            'total_words_per_label': total_words_per_label,
            'vocab_size': vocab_size
        }

    def predict_label(self, text, model):
        words = clean_text(text)
        labels = model['prior_log_probabilities'].keys()
        log_probabilities = {}

        # defining a minimum probability to prevent log(0)
        min_prob = 1e-10  

        for label in labels:

            log_prob = model['prior_log_probabilities'][label]
            total_word_count = model['total_words_per_label'][label]
            vocab_size = model['vocab_size']

            for word in set(words): 

                if word in model['vocabulary']:
                    log_prob += model['conditional_log_probabilities'][label].get(word, math.log((0 + 1.0) / (total_word_count + vocab_size)))
                else:
                    log_prob += math.log((0 + 1.0) / (total_word_count + vocab_size))

            log_probabilities[label] = log_prob

        return max(log_probabilities, key=log_probabilities.get)

    def __init__(self):
        self.training_set = []
        self.testing_set = []

    def process(self, training_data, label, text):
        if label is not None:
            if training_data:
                self.training_set.append((label, text))
            else:
                self.testing_set.append((label, text))

    def end_partition(self):
        # training the naive bayes model
        model = self.train_model(self.training_set)

        # predicting labels for the test set
        for actual_label, text in self.testing_set:
            predicted_label = self.predict_label(text, model)
            yield (text, actual_label, predicted_label)

$$;

DROP TABLE IF EXISTS sentiment_results;

-- running the UDTF and storing the results
CREATE OR REPLACE TABLE sentiment_results AS
SELECT output.*
FROM training_or_testing AS t,
     TABLE(sentiment_analysis_udtf(t.training_data, t.label, t.text) OVER (PARTITION BY 1)) AS output;

-- precision per label
CREATE OR REPLACE VIEW precision_per_label AS
SELECT
    predicted_label AS label,
    SUM(CASE WHEN predicted_label = true_label THEN 1 ELSE 0 END) AS true_positives,
    SUM(CASE WHEN predicted_label <> true_label THEN 1 ELSE 0 END) AS false_positives,
    (SUM(CASE WHEN predicted_label = true_label THEN 1 ELSE 0 END) * 100.0) /
    NULLIF(SUM(CASE WHEN predicted_label = true_label THEN 1 ELSE 0 END) + SUM(CASE WHEN predicted_label <> true_label THEN 1 ELSE 0 END), 0) AS precision_percentage
FROM sentiment_results
GROUP BY predicted_label
ORDER BY precision_percentage DESC;

-- precision per label
-- SELECT * FROM precision_per_label;

-- calculating overall precision
SELECT
    (SUM(true_positives) * 100.0) / NULLIF(SUM(true_positives + false_positives), 0) AS overall_precision_percentage
FROM precision_per_label;