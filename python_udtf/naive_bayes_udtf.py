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