# Elasticsearch — Query DSL, Text Analysis & Search Features
> Covers Elasticsearch 8.x (Elasticsearch in Action, 2nd Ed — Konda, Manning 2023)

---

## The Query DSL Taxonomy

Every search in Elasticsearch is a JSON document sent to `_search`. Queries fall into four families:

```
Query DSL
├── Term-level queries   — exact match, no analysis; operate on indexed terms as-is
│   (term, terms, range, prefix, wildcard, regexp, fuzzy, exists, ids, terms_set)
│
├── Full-text queries    — run through the same analyzer used at index time; scored
│   (match, match_phrase, match_phrase_prefix, match_bool_prefix,
│    multi_match, query_string, simple_query_string, combined_fields, intervals)
│
├── Compound queries     — combine/modify other queries
│   (bool, boosting, constant_score, dis_max, function_score, script_score)
│
└── Specialized queries  — geo, nested, join, vector, percolator, MLT
    (nested, has_child, has_parent, geo_distance, geo_bounding_box,
     geo_shape, knn, more_like_this, percolate, span_*, script_score)
```

**Critical distinction**: Term-level queries bypass the analyzer. `term: { "title": "Elasticsearch" }` will NOT match a document where "Elasticsearch" was indexed as "elasticsearch" (lowercased by the standard analyzer). Full-text queries run through the same analyzer, so case is normalised. This is the single most common source of bugs in new ES users.

---

## Part 1: Text Analysis Pipeline

### The Three-Stage Pipeline

Every `text` field passes through this chain at **index time** and at **query time** (for full-text queries):

```
Raw text: "<p>Elasticsearch is <b>FAST</b> & scalable!</p>"
              │
              ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STAGE 1: Character Filters (zero or more, applied in order)        │
│  html_strip      → "Elasticsearch is FAST & scalable!"             │
│  mapping filter  → "&" → "and" (if configured)                      │
│  pattern_replace → custom regex replacements                        │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STAGE 2: Tokenizer (exactly one)                                   │
│  standard    → ["Elasticsearch", "is", "FAST", "and", "scalable"]  │
│  whitespace  → ["Elasticsearch", "is", "FAST", "&", "scalable!"]   │
│  keyword     → ["Elasticsearch is FAST & scalable!"]  (no split)   │
│  ngram       → ["El","la","as","st",...] (all character n-grams)    │
│  edge_ngram  → ["E","El","Ela","Elas","Elast",...]                  │
│  uax_url_email → preserves URLs and emails as single tokens         │
│  path_hier.  → ["/usr", "/usr/local", "/usr/local/bin"]             │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│  STAGE 3: Token Filters (zero or more, applied in order)            │
│  lowercase     → ["elasticsearch", "is", "fast", "and", "scalable"]│
│  stop          → ["elasticsearch", "fast", "scalable"]  (drop "is","and")│
│  stemmer       → ["elasticsearch", "fast", "scalabl"]  (English)   │
│  synonym       → "fast" → ["fast", "quick", "rapid"]               │
│  asciifolding  → "café" → "cafe"                                    │
│  shingle       → ["elasticsearch fast", "fast scalable"] (bigrams) │
│  word_delimiter_graph → "Wi-Fi" → ["Wi", "Fi", "WiFi"]             │
└─────────────────────────────────────────────────────────────────────┘
```

### Tokenizers Reference

| Tokenizer | How It Splits | Best For | Example Input → Tokens |
|-----------|--------------|----------|----------------------|
| `standard` | Unicode word boundaries + lowercase | General text, prose | "Hello World!" → ["Hello", "World"] |
| `whitespace` | Whitespace only; preserves punctuation | Log parsing, code | "foo.bar baz" → ["foo.bar", "baz"] |
| `keyword` | No splitting — entire value is one token | Exact-match fields (IDs, enums) | "order-123" → ["order-123"] |
| `pattern` | Split on regex | CSV, delimited data | `pattern: ","` on "a,b,c" → ["a","b","c"] |
| `letter` | Split on non-letter characters | Simple word extraction | "Hello, World!" → ["Hello", "World"] |
| `ngram` | All character n-grams in a sliding window | Substring search | min=2, max=3: "abc" → ["ab","bc","abc"] |
| `edge_ngram` | N-grams anchored to start of each token | **Prefix autocomplete** | min=2, max=4: "fast" → ["fa","fas","fast"] |
| `uax_url_email` | Like standard but keeps URLs/emails whole | Log/document indexing | "email: foo@bar.com" → ["email","foo@bar.com"] |
| `path_hierarchy` | Splits filesystem paths at `/` | Faceted directory search | "/a/b/c" → ["/a","/a/b","/a/b/c"] |
| `char_group` | Split on any of a set of characters | Domain-specific tokenization | `tokenize_on_chars: ["-","_"]` |

### Token Filters Reference

| Token Filter | Effect | Key Config | Example |
|-------------|--------|-----------|---------|
| `lowercase` | Lowercases all tokens | — | "FAST" → "fast" |
| `uppercase` | Uppercases all tokens | — | rare; custom uses |
| `stop` | Removes stop words | `stopwords: _english_` | removes "the", "is", "a" |
| `stemmer` | Algorithmic stemming (reduces word to root) | `language: english` | "running" → "run"; "flies" → "fli" |
| `snowball` | Snowball stemmer (more aggressive) | `language: English` | "generously" → "generous" |
| `porter_stem` | Porter stemmer algorithm | — | "maximum" → "maxim" |
| `kstem` | KStem (less aggressive, English only) | — | "running" → "run" (conservative) |
| `synonym` | Expand or replace terms | `synonyms: ["fast,quick,rapid"]` | "quick" → ["quick","fast","rapid"] |
| `synonym_graph` | Multi-word synonyms (use at query time) | `synonyms: ["NY,New York"]` | "NY" → "New York" |
| `asciifolding` | Strips diacritics | — | "café" → "cafe"; "naïve" → "naive" |
| `word_delimiter_graph` | Splits on casing, punctuation, digits | `split_on_case_change: true` | "Wi-Fi" → ["Wi","Fi","WiFi"]; "log4j" → ["log","4j","log4j"] |
| `shingle` | Produces word n-grams | `min_shingle_size: 2` | "big red dog" → ["big red","red dog"] |
| `unique` | Deduplicates tokens | — | "the the dog" → ["the","dog"] |
| `truncate` | Truncates tokens at N chars | `length: 10` | "elasticsearch" → "elasticsea" |
| `length` | Removes tokens outside min/max length | `min: 2, max: 15` | removes single chars and very long strings |
| `ngram` (filter) | N-grams on already-tokenized stream | `min_gram: 3` | "fast" → ["fas","ast","fast"] |
| `edge_ngram` (filter) | Edge n-grams on token stream | `min_gram: 2` | "fast" → ["fa","fas","fast"] |
| `reverse` | Reverses tokens (suffix search trick) | — | "fast" → "tsaf"; pair with edge_ngram for suffix |
| `phonetic` | Soundex / Double Metaphone phonetic coding | `encoder: double_metaphone` | "smith" ≈ "smyth" (plugin required) |
| `keep_words` | Whitelist — keep only specified words | `keep_words: [...]` | |
| `multiplexer` | Apply multiple filter chains, merge results | `filters: [stemmer, synonym]` | Produces both stemmed + expanded tokens |
| `condition` | Apply filter only if Painless script returns true | `script: "..."` | |
| `fingerprint` | Sorts, deduplicates, concatenates → single token | — | Used for near-duplicate detection |

### Stemming Deep Dive

Stemming reduces inflected/derived words to a common root so "running", "runs", "runner" all match "run":

```
Algorithm comparison on "generously":
  porter_stem  → "generous"     (moderate)
  kstem        → "generously"   (conservative — may not stem)
  snowball     → "generous"     (moderate, multi-language)
  hunspell     → "generous"     (dictionary-based, most accurate, requires dict files)

On "flies":
  porter_stem  → "fli"          ← aggressive, loses morphological coherence
  kstem        → "fly"          ← correct
  snowball     → "fli"          ← aggressive

Recommendation: kstem for English (less aggressive, better precision);
                snowball for non-English European languages;
                hunspell when accuracy > performance (loads dictionary into heap)
```

**Stemmer vs. Lemmatiser**: Stemming is algorithmic (fast, may produce non-words like "fli"). Lemmatisation uses morphological analysis to return actual dictionary forms ("flies" → "fly"). Elasticsearch's built-in stemmers are algorithmic; use `hunspell` for dictionary-based lemmatisation.

### Custom Analyzer Example (Production Pattern)

```json
PUT /products
{
  "settings": {
    "analysis": {
      "char_filter": {
        "html_strip_filter": { "type": "html_strip" },
        "brand_normalizer": {
          "type": "mapping",
          "mappings": ["& => and", "@ => at"]
        }
      },
      "tokenizer": {
        "edge_ngram_tokenizer": {
          "type": "edge_ngram",
          "min_gram": 2,
          "max_gram": 20,
          "token_chars": ["letter", "digit"]
        }
      },
      "filter": {
        "english_stop": { "type": "stop", "stopwords": "_english_" },
        "english_stemmer": { "type": "stemmer", "language": "english" },
        "product_synonyms": {
          "type": "synonym_graph",
          "synonyms": [
            "tv, television, telly",
            "laptop, notebook, macbook",
            "mobile, smartphone, phone, cell"
          ]
        }
      },
      "analyzer": {
        "product_search_analyzer": {
          "type": "custom",
          "char_filter": ["html_strip_filter", "brand_normalizer"],
          "tokenizer": "standard",
          "filter": ["lowercase", "english_stop", "product_synonyms", "english_stemmer"]
        },
        "product_autocomplete_analyzer": {
          "type": "custom",
          "tokenizer": "edge_ngram_tokenizer",
          "filter": ["lowercase"]
        },
        "product_autocomplete_search_analyzer": {
          "type": "custom",
          "tokenizer": "standard",
          "filter": ["lowercase"]
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "name": {
        "type": "text",
        "analyzer": "product_search_analyzer",
        "fields": {
          "autocomplete": {
            "type": "text",
            "analyzer": "product_autocomplete_analyzer",
            "search_analyzer": "product_autocomplete_search_analyzer"
          },
          "keyword": { "type": "keyword" }
        }
      }
    }
  }
}
```

**Key insight**: The `name` field has three sub-representations:
- `name` (text) — analyzed with synonyms + stemming for full-text relevance search
- `name.autocomplete` (text) — edge_ngram at index, standard at search = prefix autocomplete
- `name.keyword` (keyword) — exact match, sorting, aggregation

### Testing Your Analyzer

```bash
# Test what tokens an analyzer produces
GET /products/_analyze
{
  "analyzer": "product_search_analyzer",
  "text": "Apple MacBook Pro laptops"
}
# Response shows: tokens, start_offset, end_offset, type, position
# Tokens: ["appl", "macbook", "pro", "laptop", "notebook"]
#         ↑ stemmed  ↑ kept    ↑     ↑ synonym expanded
```

---

## Part 2: Term-Level Queries (No Analysis)

Term-level queries match **exact indexed terms**. They bypass the analyzer — what you send in the query is compared verbatim against the inverted index.

### `term` — Exact Single-Value Match

```json
// Exact match on a keyword field
GET /products/_search
{
  "query": {
    "term": {
      "category.keyword": {
        "value": "Electronics",
        "boost": 1.5          // optional relevance boost
      }
    }
  }
}

// WRONG: term query on an analyzed text field
// Stored term: "electronics" (lowercased)
// Query term: "Electronics" (not lowercased)
// → ZERO results
{ "query": { "term": { "category": "Electronics" } } }  // ← bug!
```

### `terms` — Match Any of N Values (IN clause)

```json
GET /products/_search
{
  "query": {
    "terms": {
      "status.keyword": ["active", "pending", "on_sale"],
      "boost": 1.0
    }
  }
}

// Terms lookup — fetch the list of values from another document
// Useful for "show me products that user's wishlist contains"
GET /products/_search
{
  "query": {
    "terms": {
      "product_id": {
        "index": "wishlists",
        "id": "user-456",
        "path": "product_ids"
      }
    }
  }
}
```

### `range` — Numeric, Date, and String Ranges

```json
GET /products/_search
{
  "query": {
    "range": {
      "price": { "gte": 10.0, "lte": 100.0 }
    }
  }
}

// Date range with math
{
  "query": {
    "range": {
      "created_at": {
        "gte": "now-7d/d",    // 7 days ago, rounded to day
        "lte": "now/d",       // today, rounded to day
        "format": "strict_date_optional_time"
      }
    }
  }
}

// Date math operators:
// now-1h  (1 hour ago)   now+2d  (2 days ahead)
// /d      (round down to day)   /M (round to month)
// now-1d/d = yesterday start;  now/d+1d-1ms = today end
```

### `prefix` — Terms Starting With a String

```json
// Matches "elasticsearch", "elastic", "elasticity" etc.
GET /products/_search
{
  "query": {
    "prefix": {
      "brand.keyword": {
        "value": "elast",
        "rewrite": "constant_score"   // performance: use constant score (no per-doc score)
      }
    }
  }
}
```

**Performance warning**: `prefix` queries on high-cardinality `keyword` fields scan the term dictionary linearly from the prefix. For autocomplete on large fields, `edge_ngram` is 10–100× faster because matching is just an inverted index lookup. See Part 5 (Autocomplete) for the comparison.

### `wildcard` — Glob Patterns on Terms

```json
{
  "query": {
    "wildcard": {
      "email.keyword": {
        "value": "*@gmail.com",
        "case_insensitive": true    // ES 7.10+
      }
    }
  }
}
// * = any sequence of characters
// ? = any single character
```

**Performance**: Leading wildcard (`*@gmail.com`) is extremely expensive — forces a full term dictionary scan. Avoid in production. If you need suffix search, index a `reversed` field (apply `reverse` token filter) and use prefix query on reversed values.

### `regexp` — Regular Expressions on Terms

```json
{
  "query": {
    "regexp": {
      "postcode.keyword": {
        "value": "[A-Z]{1,2}[0-9]{1,2}[A-Z]? [0-9][A-Z]{2}",
        "flags": "ALL",
        "case_insensitive": true,
        "rewrite": "constant_score"
      }
    }
  }
}
```

**Performance**: Regexp queries must evaluate the automaton against every term in the dictionary. Anchored patterns (starting with literal characters) are faster. Complex patterns on high-cardinality fields can cause query timeouts. Set `index.max_regexp_length` limit.

### `fuzzy` — Edit Distance (Typo Tolerance)

```json
{
  "query": {
    "fuzzy": {
      "title": {
        "value": "elasticserach",    // typo: "serach" instead of "search"
        "fuzziness": "AUTO",         // AUTO: 0 for 1-2 chars, 1 for 3-5, 2 for 6+
        "prefix_length": 3,          // first 3 chars must match exactly (performance)
        "max_expansions": 50,        // max candidate terms to try
        "transpositions": true       // allow "ab" → "ba" as 1 edit (Damerau-Levenshtein)
      }
    }
  }
}
```

**Fuzziness AUTO rules**:
| Term Length | Max Edits |
|-------------|-----------|
| 1–2 chars | 0 (exact) |
| 3–5 chars | 1 |
| 6+ chars | 2 |

### `exists` — Field Has a Non-Null Value

```json
{ "query": { "exists": { "field": "description" } } }
// Equivalent to SQL: WHERE description IS NOT NULL
// Inverse: must_not + exists = field is null/missing
```

### `ids` — Match by Document IDs

```json
{ "query": { "ids": { "values": ["123", "456", "789"] } } }
```

### `terms_set` — At Least N Terms Must Match

```json
// Document must match at least `minimum_should_match_field` of the terms
{
  "query": {
    "terms_set": {
      "required_skills": {
        "terms": ["java", "python", "scala", "spark"],
        "minimum_should_match_field": "min_skills_required",
        "minimum_should_match_script": {
          "source": "Math.min(params.num_terms, doc['min_skills'].value)"
        }
      }
    }
  }
}
```

---

## Part 3: Full-Text Queries (With Analysis)

Full-text queries run your search string through the **same analyzer used at index time**, then build a query from the resulting tokens. This is why "ELASTICSEARCH" matches documents containing "elasticsearch".

### `match` — Standard Full-Text Search

```json
GET /products/_search
{
  "query": {
    "match": {
      "description": {
        "query": "fast database writes",
        "operator": "or",             // default: OR (any token matches)
        "minimum_should_match": "75%", // at least 75% of tokens must match
        "fuzziness": "AUTO",          // adds typo tolerance
        "prefix_length": 2,
        "zero_terms_query": "none",   // or "all" — return all docs if all terms are stop words
        "auto_generate_synonyms_phrase_query": true  // expand synonyms as phrase queries
      }
    }
  }
}
```

**`operator: "and"` vs `"or"`**:
- `"or"`: match any token → higher recall, lower precision (more results)
- `"and"`: all tokens must match → lower recall, higher precision (fewer, more relevant results)
- `"minimum_should_match": "75%"` is the practical middle ground

### `match_phrase` — Exact Phrase in Order

```json
{
  "query": {
    "match_phrase": {
      "description": {
        "query": "quick brown fox",
        "slop": 2    // allow up to 2 transpositions: "quick [word] [word] brown fox" also matches
      }
    }
  }
}
```

`slop` controls phrase proximity. `slop: 0` = exact phrase. `slop: 1` = one word can be between tokens or one transposition.

### `match_phrase_prefix` — Phrase Autocomplete

```json
// "elas" → matches "elasticsearch is fast", "elastic search tutorial", etc.
{
  "query": {
    "match_phrase_prefix": {
      "title": {
        "query": "elastic sea",         // last token "sea" is treated as prefix
        "max_expansions": 50,           // max terms to expand last-token prefix to
        "slop": 1
      }
    }
  }
}
```

This is simpler than `edge_ngram` for autocomplete but slower — it expands the prefix into up to `max_expansions` terms at query time. For high-QPS autocomplete, `edge_ngram` is preferred.

### `match_bool_prefix` — Autocomplete with Relevance

```json
// Each analyzed token except the last becomes a match query;
// the last token becomes a prefix query. Combined in a bool should.
{
  "query": {
    "match_bool_prefix": {
      "title": "elasticsearch qu"
      // Expands to: bool { should: [match("elasticsearch"), prefix("qu")] }
      // "elasticsearch query" and "elasticsearch quick" both match
    }
  }
}
```

### `multi_match` — Search Across Multiple Fields

```json
{
  "query": {
    "multi_match": {
      "query": "elasticsearch distributed search",
      "fields": ["title^3", "description^1.5", "tags"],  // ^N = boost
      "type": "best_fields",    // default
      "tie_breaker": 0.3        // score = best_field_score + tie_breaker × other_fields_scores
    }
  }
}
```

**`multi_match` types**:

| Type | How Scoring Works | Best For |
|------|------------------|----------|
| `best_fields` | Score = highest single-field score + tie_breaker × others | Most fields are independent; matching concentrated in one field is best |
| `most_fields` | Score = sum of all field scores | Fields carry redundant info (title + title.english); reward multiple matches |
| `cross_fields` | Treats all fields as one virtual field | Person name split across `first_name` + `last_name`; all words must appear somewhere |
| `phrase` | `match_phrase` on each field | Phrase matching across fields |
| `phrase_prefix` | `match_phrase_prefix` on each field | Phrase autocomplete across fields |
| `bool_prefix` | `match_bool_prefix` on each field | Autocomplete across fields |

### `query_string` — Lucene Query Syntax (Power Users)

```json
{
  "query": {
    "query_string": {
      "query": "(elasticsearch OR solr) AND (fast OR performance) -deprecated",
      "fields": ["title", "description"],
      "default_operator": "AND",
      "allow_leading_wildcard": false,  // disable for performance
      "fuzziness": "AUTO",
      "phrase_slop": 3
    }
  }
}
// Supports: AND OR NOT, field:value, "phrase", wildcards, ranges [10 TO 100], boosts^
// Dangerous for user input — malformed queries throw exceptions
```

### `simple_query_string` — Safe User-Facing Search

```json
{
  "query": {
    "simple_query_string": {
      "query": "elasticsearch +fast -deprecated ~fuzzy \"exact phrase\"",
      "fields": ["title^2", "description"],
      "default_operator": "and",
      "flags": "AND|OR|NOT|PHRASE|PREFIX|FUZZY"
      // Never throws exceptions; silently ignores invalid syntax
    }
  }
}
// User operators: + (must), - (must_not), " " (phrase), * (prefix), ~ (fuzziness), | (or)
```

### `combined_fields` — Cross-Field with BM25 Normalisation

```json
// Like cross_fields multi_match but applies BM25 per virtual combined field
// Correctly handles TF/IDF statistics across fields of different lengths
{
  "query": {
    "combined_fields": {
      "query": "John Smith software engineer",
      "fields": ["first_name", "last_name", "bio"],
      "operator": "and",
      "minimum_should_match": "2"
    }
  }
}
```

### `intervals` — Precise Proximity and Ordering Rules

The `intervals` query gives fine-grained control over term proximity and ordering — more powerful than `match_phrase` with `slop`:

```json
{
  "query": {
    "intervals": {
      "description": {
        "all_of": {
          "intervals": [
            { "match": { "query": "elasticsearch", "max_gaps": 0 } },
            { "match": { "query": "fast",          "max_gaps": 5, "ordered": false } }
          ],
          "ordered": true    // elasticsearch must appear before fast
        }
      }
    }
  }
}
// Matches: "elasticsearch is blazingly fast" (gap of 3 between "elasticsearch" and "fast")
// Does not match: "fast elasticsearch" (ordered: true)
```

---

## Part 4: Compound Queries

### `bool` — The Workhorse

```json
{
  "query": {
    "bool": {
      "must": [
        { "match": { "title": "elasticsearch" } }       // affects score + filters
      ],
      "should": [
        { "match": { "description": "distributed" } },  // boosts score if matches
        { "term":  { "tags": "search" } }
      ],
      "must_not": [
        { "term": { "status": "deprecated" } }          // excludes; no score impact
      ],
      "filter": [
        { "range": { "price": { "gte": 10, "lte": 100 } } },  // no score; cached
        { "term":  { "in_stock": true } }
      ],
      "minimum_should_match": 1,    // at least 1 "should" must match
      "boost": 1.2
    }
  }
}
```

**`filter` vs `must`**: `filter` clauses do not contribute to relevance score and are **cached by ES**. Use `filter` for all non-scoring criteria (date ranges, status flags, price brackets). Use `must` when you want the clause to affect relevance.

**Caching**: Filter clauses are cached as bitsets per segment. A `term: { "status": "active" }` filter used frequently will be served from the filter cache after the first execution.

### `function_score` — Custom Scoring

```json
{
  "query": {
    "function_score": {
      "query": { "match": { "title": "elasticsearch" } },
      "functions": [
        {
          "filter": { "term": { "is_featured": true } },
          "weight": 3.0                               // multiply score by 3 for featured
        },
        {
          "field_value_factor": {
            "field": "review_count",
            "factor": 1.2,
            "modifier": "log1p",    // score × log(1 + review_count × 1.2)
            "missing": 1
          }
        },
        {
          "gauss": {
            "price": {
              "origin": "50",          // ideal price
              "scale":  "20",          // at ±20 from origin, score = decay
              "offset": "10",          // no decay within ±10 of origin
              "decay":  0.5            // at origin±scale, score × 0.5
            }
          }
        }
      ],
      "score_mode": "sum",    // how to combine function scores: multiply|sum|avg|first|max|min
      "boost_mode": "sum"     // how to combine with query score: multiply|replace|sum|avg|max|min
    }
  }
}
```

**Decay functions** (`gauss`, `exp`, `linear`):

```
gauss:   bell curve — score decays smoothly from origin
exp:     exponential — steeper drop-off
linear:  linear decay — uniform drop per unit distance from origin
```

Used for geo-distance boosting, time freshness boosting, price proximity boosting.

### `script_score` — Arbitrary Painless Scoring

```json
{
  "query": {
    "script_score": {
      "query": { "match": { "description": "fast search" } },
      "script": {
        "source": """
          double recency = 1.0 / (1.0 + Math.log1p((System.currentTimeMillis() - doc['published_at'].value.millis) / 86400000.0));
          double popularity = Math.log1p(doc['view_count'].value);
          return _score * recency * popularity;
        """
      }
    }
  }
}
```

**Performance note**: Painless scripts are JIT-compiled by ES but are ~5–10× slower than native query scoring. Use for complex re-ranking on a small candidate set; avoid on queries scanning millions of documents.

### `boosting` — Positive/Negative Boost

```json
{
  "query": {
    "boosting": {
      "positive": { "match": { "title": "elasticsearch" } },
      "negative": { "term":  { "tags": "legacy" } },
      "negative_boost": 0.2    // documents matching negative get score × 0.2
    }
  }
}
// Demotes but does NOT exclude legacy-tagged results
```

### `dis_max` — Disjunction Maximum

```json
{
  "query": {
    "dis_max": {
      "queries": [
        { "match": { "title": { "query": "elasticsearch", "boost": 3 } } },
        { "match": { "description": "elasticsearch" } }
      ],
      "tie_breaker": 0.3
    }
  }
}
// Final score = max(field scores) + tie_breaker × sum(other field scores)
// Prevents double-counting when the same term appears in multiple fields
```

### `constant_score` — Filter Without Scoring Overhead

```json
{
  "query": {
    "constant_score": {
      "filter": { "term": { "category": "electronics" } },
      "boost": 1.5    // all matching docs get score = 1.5
    }
  }
}
// Useful when you only want filtering behaviour (no scoring) from a query
```

---

## Part 5: Prefix & Autocomplete Features

Elasticsearch has four mechanisms for autocomplete. Each has a different performance and flexibility profile:

### Mechanism 1: `edge_ngram` Tokenizer (Recommended for Most Cases)

```
Index time: "elastic" → ["el", "ela", "elas", "elast", "elasti", "elastic"]
Query time: standard tokenizer → "ela" (exact term lookup on edge_ngram tokens)
```

```json
// Mapping
"title": {
  "type": "text",
  "fields": {
    "suggest": {
      "type": "text",
      "analyzer": "autocomplete_index_analyzer",   // edge_ngram at index
      "search_analyzer": "autocomplete_search_analyzer"  // standard at search
    }
  }
}

// Query: match on the suggest sub-field
{ "query": { "match": { "title.suggest": "ela" } } }
```

**Why different analyzers?** At index time you want edge_ngrams stored. At query time you do NOT want to edge_ngram the query — you just want the exact prefix term "ela" to match the stored ngram "ela". If you apply edge_ngram at search time too, "ela" → ["el","ela"] which creates spurious matches.

### Mechanism 2: `search_as_you_type` Field Type (ES 7.2+)

A dedicated field type that pre-creates a shingle analyzer specifically for autocomplete — cleaner than manually building edge_ngram analyzers:

```json
"mappings": {
  "properties": {
    "product_name": {
      "type": "search_as_you_type"
      // Automatically creates sub-fields:
      // product_name             (2-shard-gram based)
      // product_name._2gram      (bigram shingles)
      // product_name._3gram      (trigram shingles)
      // product_name._index_prefix (edge_ngram on last token)
    }
  }
}

// Query: multi_match bool_prefix across all sub-fields
{
  "query": {
    "multi_match": {
      "query": "elastic sea",
      "type": "bool_prefix",
      "fields": [
        "product_name",
        "product_name._2gram",
        "product_name._3gram"
      ]
    }
  }
}
```

**What it does**: `search_as_you_type` indexes shingles (word bigrams and trigrams) + edge_ngrams on the final token. Matching on shingles ensures intermediate words in multi-word prefixes score correctly: "elastic sea" correctly ranks "elastic search engine" over "sea elastic engine" because the bigram "elastic sea" is directly indexed.

### Mechanism 3: `completion` Suggester (Fastest, Least Flexible)

The `completion` suggester uses a **Finite State Transducer (FST)** stored in memory — lookups are O(length of prefix), typically < 1ms:

```json
// Mapping
"mappings": {
  "properties": {
    "suggest": {
      "type": "completion",
      "analyzer": "simple",         // lowercase, no stemming
      "preserve_separators": true,
      "preserve_position_increments": true,
      "max_input_length": 50
    }
  }
}

// Index a document with suggest input + weight
PUT /products/_doc/1
{
  "name": "Elasticsearch",
  "suggest": {
    "input": ["elasticsearch", "elastic search", "ES"],  // multiple inputs per doc
    "weight": 42                                          // boost in suggestions list
  }
}

// Query
GET /products/_search
{
  "suggest": {
    "product-suggest": {
      "prefix": "elast",
      "completion": {
        "field": "suggest",
        "size": 10,
        "skip_duplicates": true,
        "fuzzy": { "fuzziness": 1 },     // optional typo tolerance
        "contexts": {                     // optional context filtering
          "category": [{ "context": "electronics" }]
        }
      }
    }
  }
}
```

**FST vs edge_ngram**:
| | completion (FST) | edge_ngram |
|--|:----------------:|:----------:|
| Latency | < 1ms | 1–5ms |
| Filtering | Context only | Full query DSL |
| Relevance ranking | Weight field only | Full BM25 + function_score |
| Multi-word prefix | ✅ | Complex (use search_as_you_type) |
| Memory | Held in JVM off-heap | Page cache |

### Mechanism 4: `prefix` Query on `keyword` Field

```json
{ "query": { "prefix": { "brand.keyword": "apple" } } }
```

Simple but does a linear term dictionary scan. Acceptable for low-cardinality fields (< 10K unique values). Do not use on high-cardinality fields — use edge_ngram instead.

### Summary: Which Autocomplete Mechanism to Use

```
Need sub-1ms, simple prefix, weight-based ranking?
  → completion suggester

Need prefix + full query DSL (filters, function_score, geo)?
  → edge_ngram + search_as_you_type

Need multi-word autocomplete with relevance (most common production case)?
  → search_as_you_type (simplest config)
  → or custom edge_ngram + match_bool_prefix

Simple low-cardinality exact prefix on a keyword field?
  → prefix query
```

---

## Part 6: Suggesters

### Term Suggester (Did You Mean?)

```json
GET /products/_search
{
  "suggest": {
    "did-you-mean": {
      "text": "elasticserch",           // user's typo
      "term": {
        "field": "title",
        "sort": "score",                // or "frequency"
        "suggest_mode": "missing",      // always | missing | popular
        "min_word_length": 4,
        "prefix_length": 2,             // first 2 chars must match exactly
        "max_edits": 2                  // max Levenshtein distance
      }
    }
  }
}
// Returns: "elasticserch" → suggestions: ["elasticsearch", "elasticsearcher"]
```

### Phrase Suggester (Whole Phrase Correction)

```json
{
  "suggest": {
    "phrase-correction": {
      "text": "elasticsearch distrubuted serch",
      "phrase": {
        "field": "description.shingle",     // field must have shingle sub-field
        "gram_size": 2,
        "real_word_error_likelihood": 0.95,
        "max_errors": 0.5,
        "confidence": 1.0,
        "direct_generator": [
          { "field": "description.shingle", "suggest_mode": "always" }
        ],
        "highlight": {
          "pre_tag": "<em>",
          "post_tag": "</em>"
        }
      }
    }
  }
}
// Returns: "elasticsearch distributed search"
```

---

## Part 7: Aggregations

Aggregations are ES's analytics engine — compute metrics, group documents, and pipeline results:

```
Aggregation types:
├── Metric      → compute a single value over a field (avg, sum, max, cardinality...)
├── Bucket      → group documents into buckets (terms, range, date_histogram...)
└── Pipeline    → compute over the results of other aggregations (moving_avg, derivative...)
```

### Metric Aggregations

```json
GET /orders/_search
{
  "size": 0,    // don't return documents, only aggregation results
  "aggs": {
    "avg_price":         { "avg":           { "field": "price" } },
    "total_revenue":     { "sum":           { "field": "price" } },
    "max_price":         { "max":           { "field": "price" } },
    "price_stats":       { "stats":         { "field": "price" } },    // count+min+max+avg+sum
    "price_ext_stats":   { "extended_stats": { "field": "price" } },  // + std_dev, variance
    "unique_customers":  { "cardinality":   { "field": "customer_id", "precision_threshold": 3000 } },
    "price_percentiles": {
      "percentiles": {
        "field": "price",
        "percents": [50, 90, 95, 99],
        "hdr": { "number_of_significant_value_digits": 3 }  // HdrHistogram for accuracy
      }
    },
    "price_percentile_ranks": {
      "percentile_ranks": { "field": "price", "values": [10, 50, 100] }
    },
    "top_3_orders": {
      "top_hits": { "size": 3, "sort": [{ "price": "desc" }], "_source": ["id", "customer"] }
    }
  }
}
```

**`cardinality` accuracy**: Uses HyperLogLog++. `precision_threshold: 3000` → error < 1% for cardinalities < 3000. Higher threshold = more heap. For exact counts, use `terms` aggregation (but can't handle millions of unique values).

### Bucket Aggregations

```json
GET /orders/_search
{
  "size": 0,
  "aggs": {
    // terms: group by field value (like SQL GROUP BY)
    "by_category": {
      "terms": {
        "field": "category.keyword",
        "size": 10,                     // top 10 categories
        "min_doc_count": 5,             // ignore categories with < 5 docs
        "order": { "_count": "desc" },  // or { "_key": "asc" } or sub-agg name
        "show_term_doc_count_error": true,
        "shard_size": 50                // fetch top 50 per shard, merge globally to top 10
      },
      "aggs": {
        "total_revenue": { "sum": { "field": "price" } }  // nested agg per bucket
      }
    },

    // range: custom numeric buckets
    "price_bands": {
      "range": {
        "field": "price",
        "ranges": [
          { "to": 25 },
          { "from": 25, "to": 50 },
          { "from": 50, "to": 100 },
          { "from": 100 }
        ]
      }
    },

    // date_histogram: time-series bucketing
    "orders_over_time": {
      "date_histogram": {
        "field": "created_at",
        "calendar_interval": "1d",    // day | week | month | quarter | year
        "time_zone": "America/New_York",
        "min_doc_count": 0,           // include empty buckets
        "extended_bounds": { "min": "2024-01-01", "max": "2024-12-31" }
      }
    },

    // histogram: numeric bucketing at fixed interval
    "price_histogram": {
      "histogram": { "field": "price", "interval": 10, "min_doc_count": 0 }
    },

    // filter: single-condition bucket
    "expensive_orders": {
      "filter": { "range": { "price": { "gte": 500 } } },
      "aggs": { "avg_price": { "avg": { "field": "price" } } }
    },

    // filters: multiple named filter buckets
    "order_segments": {
      "filters": {
        "filters": {
          "cheap":     { "range": { "price": { "lt": 25 } } },
          "mid_range": { "range": { "price": { "gte": 25, "lt": 100 } } },
          "premium":   { "range": { "price": { "gte": 100 } } }
        }
      }
    },

    // composite: paginate through all bucket combinations (like SQL GROUP BY ROLLUP)
    "paginated_categories": {
      "composite": {
        "size": 100,
        "sources": [
          { "category": { "terms": { "field": "category.keyword" } } },
          { "month":    { "date_histogram": { "field": "created_at", "calendar_interval": "month" } } }
        ],
        "after": { "category": "electronics", "month": 1704067200000 }  // pagination cursor
      }
    }
  }
}
```

**`terms` aggregation accuracy problem**: Each shard computes top-N independently. The coordinating node merges shard results. A term with rank 11 on most shards but total rank 1 globally is undercount. Solution: increase `shard_size` (default `size × 1.5 + 10`). To avoid entirely, use `composite` aggregation for full correctness.

### Pipeline Aggregations

```json
"aggs": {
  "orders_by_day": {
    "date_histogram": { "field": "created_at", "calendar_interval": "day" },
    "aggs": {
      "daily_revenue": { "sum": { "field": "price" } },

      // Pipeline: moving average over daily revenue buckets
      "revenue_moving_avg": {
        "moving_avg": {
          "buckets_path": "daily_revenue",
          "window": 7,            // 7-day rolling average
          "model": "simple"       // or "linear", "ewma", "holt", "holt_winters"
        }
      },

      // Pipeline: derivative (day-over-day change)
      "revenue_derivative": {
        "derivative": { "buckets_path": "daily_revenue" }
      },

      // Pipeline: cumulative sum
      "cumulative_revenue": {
        "cumulative_sum": { "buckets_path": "daily_revenue" }
      }
    }
  },

  // Sibling pipeline: across all day buckets
  "best_day_revenue": { "max_bucket": { "buckets_path": "orders_by_day>daily_revenue" } },
  "worst_day_revenue": { "min_bucket": { "buckets_path": "orders_by_day>daily_revenue" } },
  "avg_daily_revenue": { "avg_bucket": { "buckets_path": "orders_by_day>daily_revenue" } }
}
```

---

## Part 8: Highlighting

```json
GET /articles/_search
{
  "query": { "match": { "body": "elasticsearch distributed" } },
  "highlight": {
    "pre_tags": ["<strong>"],
    "post_tags": ["</strong>"],
    "fields": {
      "body": {
        "type": "unified",           // unified (default), plain, fvh
        "fragment_size": 150,        // chars per snippet
        "number_of_fragments": 3,    // max snippets to return
        "no_match_size": 100,        // chars to return if no match in field
        "order": "score",            // score | none
        "highlight_query": {         // optionally different query for highlighting
          "match_phrase": { "body": "elasticsearch distributed" }
        }
      }
    }
  }
}
```

**Highlighter types**:
| Type | How It Works | Best For |
|------|-------------|----------|
| `unified` (default) | Breaks into sentences using ICU, scores + highlights | General use; good quality |
| `plain` | Re-analyzes stored text; no positional data needed | When term_vector not stored |
| `fvh` (fast vector highlighter) | Uses pre-stored term vectors; fastest | Large fields, high QPS — requires `term_vector: with_positions_offsets` in mapping |

---

## Part 9: Geo Search

```json
// Mapping
"location": { "type": "geo_point" }

// Geo-distance query
{
  "query": {
    "geo_distance": {
      "distance": "10km",
      "distance_type": "arc",    // arc (accurate) or plane (faster for small distances)
      "location": { "lat": 40.7128, "lon": -74.0060 }
    }
  }
}

// Sort by distance
"sort": [
  {
    "_geo_distance": {
      "location": { "lat": 40.7128, "lon": -74.0060 },
      "order": "asc",
      "unit": "km",
      "distance_type": "arc"
    }
  }
]

// Geo-distance aggregation (concentric rings: within 5km, 5-10km, 10-50km)
"aggs": {
  "rings_around_me": {
    "geo_distance": {
      "field": "location",
      "origin": { "lat": 40.7128, "lon": -74.0060 },
      "unit": "km",
      "ranges": [
        { "to": 5 },
        { "from": 5, "to": 10 },
        { "from": 10, "to": 50 }
      ]
    }
  }
}

// Geo bounding box
{
  "query": {
    "geo_bounding_box": {
      "location": {
        "top_left":     { "lat": 40.73, "lon": -74.1 },
        "bottom_right": { "lat": 40.01, "lon": -71.12 }
      }
    }
  }
}

// Geo shape (polygon, line, circle, envelope)
{
  "query": {
    "geo_shape": {
      "area": {
        "shape": {
          "type": "polygon",
          "coordinates": [[
            [-74.1, 40.73], [-74.1, 40.01], [-71.12, 40.01], [-71.12, 40.73], [-74.1, 40.73]
          ]]
        },
        "relation": "within"    // within | intersects | disjoint | contains
      }
    }
  }
}
```

---

## Part 10: Nested and Parent-Child Documents

### Nested Objects (Correlated Sub-Documents)

**Problem with plain `object` arrays**: Elasticsearch flattens arrays of objects, losing correlation:

```
Document: { "orders": [{"product": "shoes", "qty": 2}, {"product": "hat", "qty": 1}] }
Flattened: orders.product: ["shoes", "hat"], orders.qty: [2, 1]
Query for product=hat AND qty=2 → FALSE MATCH (qty 2 is for shoes, not hat)
```

**Solution**: `nested` type stores each array element as a hidden child document:

```json
// Mapping
"orders": {
  "type": "nested",
  "properties": {
    "product": { "type": "keyword" },
    "qty":     { "type": "integer" }
  }
}

// Query: nested query to maintain correlation
{
  "query": {
    "nested": {
      "path": "orders",
      "query": {
        "bool": {
          "must": [
            { "term":  { "orders.product": "hat" } },
            { "range": { "orders.qty": { "gte": 1 } } }
          ]
        }
      },
      "score_mode": "avg",        // avg | sum | min | max | none
      "inner_hits": { "size": 3 } // return matching inner docs
    }
  }
}
```

**Cost**: Nested documents are stored as hidden Lucene documents. Each nested object = 1 hidden document. 1 product with 100 order lines = 101 documents stored.

### Parent-Child Join (Separate Documents with Relationship)

```json
// Mapping — single index, separate documents with join field
"mappings": {
  "properties": {
    "join_field": {
      "type": "join",
      "relations": { "question": "answer" }
    }
  }
}

// Index parent document
PUT /qa/_doc/1
{ "title": "What is Elasticsearch?", "join_field": "question" }

// Index child document — MUST route to same shard as parent
PUT /qa/_doc/2?routing=1
{ "body": "It's a distributed search engine.", "join_field": { "name": "answer", "parent": "1" } }

// has_child query
{
  "query": {
    "has_child": {
      "type": "answer",
      "query": { "match": { "body": "distributed" } },
      "min_children": 1,
      "max_children": 10,
      "score_mode": "max"    // none | avg | sum | max | min
    }
  }
}

// has_parent query
{
  "query": {
    "has_parent": {
      "parent_type": "question",
      "query": { "match": { "title": "elasticsearch" } },
      "score": true
    }
  }
}
```

**Nested vs parent-child**:
| | Nested | Parent-Child |
|--|:------:|:------------:|
| Storage | Same Lucene doc | Separate docs, same shard |
| Update cost | Re-index entire parent | Update child independently |
| Query overhead | Moderate | Higher (requires join at query time) |
| Best for | Small, tightly coupled arrays | Large, independently updated children |

---

## Part 11: Runtime Fields and Scripted Fields

### Runtime Fields (ES 7.11+) — Schema-on-Read

```json
// Add a runtime field to the mapping (no re-indexing needed)
PUT /orders/_mapping
{
  "runtime": {
    "price_with_tax": {
      "type": "double",
      "script": {
        "source": "emit(doc['price'].value * 1.2)"
      }
    }
  }
}

// Or define at query time only
GET /orders/_search
{
  "runtime_mappings": {
    "full_name": {
      "type": "keyword",
      "script": { "source": "emit(doc['first_name'].value + ' ' + doc['last_name'].value)" }
    }
  },
  "query": { "match": { "full_name": "John Smith" } },
  "fields": ["full_name"]
}
```

**Use case**: Compute derived fields without re-indexing. Slower than stored fields but useful for one-off analytics or schema evolution.

---

## Part 12: kNN (Vector) Search

Since ES 8.0, vector search is first-class via the `dense_vector` field with HNSW indexing:

```json
// Mapping
"mappings": {
  "properties": {
    "title_embedding": {
      "type": "dense_vector",
      "dims": 768,                 // must match your embedding model's output
      "index": true,               // enable HNSW ANN index
      "similarity": "cosine",      // cosine | dot_product | l2_norm | max_inner_product
      "index_options": {
        "type": "hnsw",
        "m": 16,                   // HNSW connections per layer (higher = more accurate, more RAM)
        "ef_construction": 100     // beam width during construction (higher = more accurate, slower build)
      }
    }
  }
}

// kNN search (top-level)
GET /articles/_search
{
  "knn": {
    "field": "title_embedding",
    "query_vector": [0.12, -0.34, ...],    // 768-dim vector from your embedding model
    "k": 10,                                // return top 10 ANN results
    "num_candidates": 100                   // beam width at query time (higher = more accurate)
  }
}

// Hybrid search: kNN + BM25 combined via Reciprocal Rank Fusion
GET /articles/_search
{
  "retriever": {
    "rrf": {
      "retrievers": [
        {
          "standard": {
            "query": { "match": { "title": "elasticsearch fast search" } }
          }
        },
        {
          "knn": {
            "field": "title_embedding",
            "query_vector": [0.12, -0.34, ...],
            "k": 50,
            "num_candidates": 100
          }
        }
      ],
      "rank_constant": 60,    // RRF parameter k
      "rank_window_size": 100
    }
  }
}
```

---

## Part 13: Index Aliases and Data Streams

### Aliases — Zero-Downtime Re-Indexing

```json
// Create alias pointing to current index
POST /_aliases
{
  "actions": [
    { "add": { "index": "products_v1", "alias": "products" } }
  ]
}

// Re-index into v2, then atomically swap the alias
POST /_reindex
{ "source": { "index": "products_v1" }, "dest": { "index": "products_v2" } }

POST /_aliases
{
  "actions": [
    { "remove": { "index": "products_v1", "alias": "products" } },
    { "add":    { "index": "products_v2", "alias": "products" } }
  ]
}
// Zero downtime — the alias swap is atomic; reads/writes flip instantly
```

### Filtered Alias (Multi-Tenancy)

```json
// Tenant A sees only their data via alias
POST /_aliases
{
  "actions": [{
    "add": {
      "index": "all_orders",
      "alias": "tenant_a_orders",
      "filter": { "term": { "tenant_id": "tenant_a" } },
      "routing": "tenant_a"    // route queries to tenant_a's shard
    }
  }]
}
```

### Data Streams (ES 7.9+) — Modern Time-Series Pattern

Data streams are the production-grade replacement for manually managing time-series indices:

```json
// 1. Create an index lifecycle policy
PUT /_ilm/policy/logs-policy { ... }

// 2. Create an index template pointing to the policy
PUT /_index_template/logs-template
{
  "index_patterns": ["logs-*"],
  "data_stream": {},              // enables data stream mode
  "template": {
    "settings": { "index.lifecycle.name": "logs-policy" },
    "mappings": { ... }
  }
}

// 3. Create the data stream (auto-creates first backing index)
PUT /_data_stream/logs-app

// 4. Index documents (always append-only via _bulk/_doc)
POST /logs-app/_doc
{ "@timestamp": "2024-01-15T10:00:00Z", "level": "ERROR", "message": "Connection refused" }
// Routing: @timestamp field is required; writes always go to the "write index" (latest backing index)
// Reads: fan out across all backing indices

// 5. Rollover creates a new backing index (triggered by ILM or manually)
POST /logs-app/_rollover
```

---

## Part 14: `more_like_this` and Percolator

### `more_like_this` (MLT)

```json
{
  "query": {
    "more_like_this": {
      "fields": ["title", "description"],
      "like": [
        { "_index": "articles", "_id": "42" },     // find docs similar to doc 42
        "Elasticsearch is a distributed search engine"  // or similar to this text
      ],
      "min_term_freq": 1,        // term must appear at least once in input
      "max_query_terms": 25,     // max terms extracted from input
      "min_doc_freq": 5,         // ignore terms appearing in < 5 docs
      "max_doc_freq": 1000,      // ignore extremely common terms
      "minimum_should_match": "30%",
      "boost_terms": 1.5,
      "include": false           // exclude the source document from results
    }
  }
}
```

### Percolator — Reverse Search (Store Queries, Match Documents)

```json
// Use case: "alert me when a new article matches my saved search"

// 1. Mapping for the percolator index
PUT /alerts
{
  "mappings": {
    "properties": {
      "query": { "type": "percolator" },       // stores a query
      "user_id": { "type": "keyword" }
    }
  }
}

// 2. Store a user's saved search as a percolator query
PUT /alerts/_doc/user-123-alert
{
  "user_id": "user-123",
  "query": {
    "bool": {
      "must": [
        { "match": { "title": "elasticsearch" } },
        { "term": { "category": "technology" } }
      ]
    }
  }
}

// 3. When a new article arrives, find which alerts it matches
GET /alerts/_search
{
  "query": {
    "percolate": {
      "field": "query",
      "document": {
        "title": "Elasticsearch 8.12 released with new features",
        "category": "technology"
      }
    }
  }
}
// Returns: user-123-alert → notify user-123
```

---

## FAANG Interview Callout: Full Query DSL

**What interviewers test**: Can you design a search feature end-to-end — from mapping to query to ranking?

**The complete search design question** ("Design the search for an e-commerce site"):

> "I'd design three query paths. First, the main search: a `bool` query with a `must` `multi_match` across title, description, and category fields (best_fields with title^3 boost), filtered by `in_stock: true` and optional price range in the `filter` clause (cached). The `function_score` wrapper adds decay on price proximity to the user's typical spend and a weight boost for featured products.
>
> Second, autocomplete: a `search_as_you_type` field on product name, queried with `multi_match: bool_prefix` across the shingle sub-fields. Under 5ms per keystroke.
>
> Third, faceted navigation: `terms` aggregations on `category.keyword`, `brand.keyword`, and `price` histogram — all in the `filter` context of the main query so facet counts reflect the filtered result set.
>
> For re-indexing (schema change or stemmer upgrade), I'd build a new index with the updated mapping, re-index via `_reindex` API with throttling, then atomically swap the alias."
