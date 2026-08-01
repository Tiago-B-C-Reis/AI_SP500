-- Prepared statement: silver_merge_news
-- Parameter ?1 = run_date (bronze dt partition, i.e. the sync batch date).
-- Key = url_hash (canonical-URL md5 computed at the edge): syndicated copies of
-- the same story collapse to one row. Scores arrive already bounded from the
-- Ollama JSON schema; the DQ suite re-verifies the bounds anyway.

MERGE INTO ai_sp500_silver.news t
USING (
    SELECT *
    FROM (
        SELECT
            url_hash,
            canonical_url,
            title,
            topic,
            source_feed,
            TRY_CAST(sentiment_score AS double)                          AS sentiment_score,
            TRY_CAST(confidence      AS double)                          AS confidence,
            TRY_CAST(relevance_sp500 AS double)                          AS relevance_sp500,
            tickers,
            event_type,
            CAST(from_iso8601_timestamp(published_at) AS timestamp)      AS published_at,
            CAST(from_iso8601_timestamp(ingested_at)  AS timestamp)      AS ingested_at,
            llm_model,
            prompt_hash,
            row_number() OVER (PARTITION BY url_hash ORDER BY ingested_at DESC) AS rn
        FROM ai_sp500_bronze.news
        WHERE dt = ?
    )
    WHERE rn = 1
) s
ON t.url_hash = s.url_hash
WHEN MATCHED THEN UPDATE SET
    sentiment_score = s.sentiment_score, confidence = s.confidence,
    relevance_sp500 = s.relevance_sp500, event_type = s.event_type,
    ingested_at = s.ingested_at, llm_model = s.llm_model, prompt_hash = s.prompt_hash
WHEN NOT MATCHED THEN INSERT
    (url_hash, canonical_url, title, topic, source_feed, sentiment_score, confidence,
     relevance_sp500, tickers, event_type, published_at, ingested_at, llm_model, prompt_hash)
    VALUES (s.url_hash, s.canonical_url, s.title, s.topic, s.source_feed, s.sentiment_score,
            s.confidence, s.relevance_sp500, s.tickers, s.event_type, s.published_at,
            s.ingested_at, s.llm_model, s.prompt_hash)
