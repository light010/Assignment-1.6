-- ============================================================================
-- FAQ UPDATE DATABASE - DATABRICKS UNITY CATALOG SCHEMA
-- Version: 4.0 (Simplified Checksum-Centric Architecture)
-- Target: Databricks Unity Catalog
-- Purpose: Complete schema for content, FAQs, and version tracking
-- Date: 2025-10-19
-- Converted from SQLite to Databricks SQL
-- ============================================================================
-- ⚠️  IMPORTANT: Unity Catalog Three-Level Namespace
-- - Format: catalog.schema.table
-- - Example: faq_catalog.faq_schema.content_repo
-- - Update the catalog and schema names below before running
-- ============================================================================

-- ============================================================================
-- CONFIGURATION - UPDATE THESE VALUES FOR YOUR ENVIRONMENT
-- ============================================================================
-- STEP 1: Uncomment and set your catalog and schema names before running:

-- USE CATALOG your_catalog_name;
-- USE SCHEMA your_schema_name;

-- Example:
-- USE CATALOG onedata_us_east_1_shared_prod;
-- USE SCHEMA faq_update;
--
-- Or use fully qualified names in CREATE TABLE statements:
-- CREATE TABLE IF NOT EXISTS your_catalog.your_schema.table_name (...)
-- ============================================================================

-- ============================================================================
-- REQUIREMENTS
-- ============================================================================
-- ✅ Databricks Runtime (DBR) 10.4 LTS or higher (for GENERATED ALWAYS AS IDENTITY)
-- ✅ Unity Catalog enabled
-- ✅ SQL Warehouse or Unity Catalog-enabled cluster
-- ✅ CREATE TABLE permission in target catalog/schema
--
-- If you have DBR < 10.4, see alternative at end of file
-- ============================================================================

-- ⚠️  WARNING: This script DROPS and RECREATES tables
-- - No backward compatibility - for DEV use only
-- - All existing data in tables will be LOST
-- - Databricks does not support transactions across table DDL
-- - Execute this script in SQL Editor or Notebook
-- ============================================================================

-- ============================================================================
-- DROP OLD TABLES (if they exist)
-- ============================================================================
-- Note: In Unity Catalog, drops are not transactional
-- IMPORTANT: Drop in reverse dependency order to avoid FK constraint errors
-- Order: Views → Child Tables → Parent Tables

-- Drop all views first (no dependencies)
DROP VIEW IF EXISTS v_detection_run_stats;
DROP VIEW IF EXISTS v_regeneration_queue;
DROP VIEW IF EXISTS v_latest_content_checksums;
DROP VIEW IF EXISTS v_content_detection_summary;
DROP VIEW IF EXISTS v_document_structure_changes;
DROP VIEW IF EXISTS v_content_changes_with_diffs;
DROP VIEW IF EXISTS v_pending_diffs;
DROP VIEW IF EXISTS v_diff_processing_stats;

-- Drop child tables (with foreign keys)
DROP TABLE IF EXISTS content_change_log;  -- Has FK to content_repo
DROP TABLE IF EXISTS faq_answers;  -- Has FK to faq_questions
DROP TABLE IF EXISTS content_diffs;  -- Removed in v4 (not needed)

-- Drop parent tables (no foreign keys pointing to them from remaining tables)
DROP TABLE IF EXISTS faq_questions;
DROP TABLE IF EXISTS content_repo;

-- ============================================================================
-- BASE TABLES (Source Data)
-- ============================================================================

-- ============================================================================
-- Table 1: content_repo
-- ============================================================================
-- Purpose: Source content repository (documents, pages, markdown extracts)
-- This is the foundation table - all content tracking references this
-- ============================================================================

CREATE TABLE IF NOT EXISTS content_repo (
    -- Primary key
    -- Note: GENERATED ALWAYS AS IDENTITY requires DBR 10.4+
    -- If you get an error, replace with: ud_source_file_id BIGINT NOT NULL
    ud_source_file_id BIGINT GENERATED ALWAYS AS IDENTITY,

    -- Organization and context
    domain STRING,
    service STRING,
    orgoid STRING,
    associateoid STRING,

    -- File identification
    raw_file_nme STRING NOT NULL,
    raw_file_type STRING,
    raw_file_version_nbr INT DEFAULT 1,
    raw_file_page_nbr INT NOT NULL,

    -- Source information
    source_url_txt STRING,
    parent_location_txt STRING,
    raw_file_path STRING,

    -- Content paths
    extracted_markdown_file_path STRING,
    extracted_layout_file_path STRING,

    -- Content metadata
    title_nme STRING,
    breadcrumb_txt STRING,
    content_tags_txt STRING,
    version_nbr INT DEFAULT 1,
    content_checksum STRING,
    file_status STRING,

    -- Timestamps
    created_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    last_modified_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
)
COMMENT 'Source content repository - foundation table for all content tracking'
TBLPROPERTIES (
    'delta.enableChangeDataFeed' = 'true',
    'delta.autoOptimize.optimizeWrite' = 'true',
    'delta.autoOptimize.autoCompact' = 'true'
);

-- Add constraints after table creation to avoid SQL Editor issues
ALTER TABLE content_repo ADD CONSTRAINT pk_content_repo PRIMARY KEY (ud_source_file_id);
ALTER TABLE content_repo ADD CONSTRAINT chk_content_checksum CHECK (content_checksum IS NULL OR LENGTH(content_checksum) = 64);
ALTER TABLE content_repo ADD CONSTRAINT chk_file_status CHECK (file_status IS NULL OR file_status IN ('Active', 'Inactive', 'Archived'));
ALTER TABLE content_repo ADD CONSTRAINT chk_page_nbr CHECK (raw_file_page_nbr > 0);

-- ============================================================================
-- Table 2: faq_questions
-- ============================================================================
-- Purpose: FAQ questions master table
-- ============================================================================

CREATE TABLE IF NOT EXISTS faq_questions (
    -- Primary key
    question_id BIGINT GENERATED ALWAYS AS IDENTITY,

    -- Question versions and history
    prev_recommended_question_txt STRING,
    prev_question_txt STRING,
    recommeded_question_txt STRING,
    question_txt STRING NOT NULL,

    -- Source information
    source STRING,
    src_file_name STRING,
    src_id STRING,
    src_page_number INT,
    prev_src STRING,

    -- Organization and context
    domain STRING,
    service STRING,
    product STRING,
    orgid STRING,

    -- Timestamps
    created TIMESTAMP,
    created_by STRING,
    modified TIMESTAMP,
    modified_by STRING,

    -- Metadata (JSON in Databricks is stored as STRING)
    version STRING,
    status STRING,
    metadata STRING
)
COMMENT 'FAQ questions master table with version history'
TBLPROPERTIES (
    'delta.enableChangeDataFeed' = 'true',
    'delta.autoOptimize.optimizeWrite' = 'true'
);

-- Add primary key constraint
ALTER TABLE faq_questions ADD CONSTRAINT pk_faq_questions PRIMARY KEY (question_id);

-- ============================================================================
-- Table 3: faq_answers
-- ============================================================================
-- Purpose: FAQ answers master table
-- ============================================================================

CREATE TABLE IF NOT EXISTS faq_answers (
    -- Primary key
    answer_id BIGINT GENERATED ALWAYS AS IDENTITY,

    -- Foreign key to question
    question_id BIGINT NOT NULL,

    -- Answer versions and history
    prev_recommended_answer_txt STRING,
    recommended_answer_txt STRING,
    prev_faq_answer_txt STRING,
    faq_answer_txt STRING NOT NULL,
    user_feedback_txt STRING,

    -- Source information
    source STRING,
    src_file_name STRING,
    src_id STRING,
    src_page_number INT,
    prev_src STRING,

    -- Organization and context
    domain STRING,
    service STRING,
    product STRING,
    orgid STRING,

    -- Timestamps
    created TIMESTAMP,
    created_by STRING,
    modified TIMESTAMP,
    modified_by STRING,

    -- Metadata
    version STRING,
    status STRING,
    metadata STRING
)
COMMENT 'FAQ answers master table linked to questions'
TBLPROPERTIES (
    'delta.enableChangeDataFeed' = 'true',
    'delta.autoOptimize.optimizeWrite' = 'true'
);

-- Add constraints after table creation
ALTER TABLE faq_answers ADD CONSTRAINT pk_faq_answers PRIMARY KEY (answer_id);

-- Foreign key constraint (optional - comment out if it causes issues)
-- Note: Foreign keys in Databricks are informational only (not enforced)
-- Uncomment the next line if you want the FK metadata:
-- ALTER TABLE faq_answers ADD CONSTRAINT fk_answers_question FOREIGN KEY (question_id) REFERENCES faq_questions(question_id);

-- ============================================================================
-- TRACKING TABLES (Version History and Change Management)
-- ============================================================================

-- ============================================================================
-- Table 4: content_change_log
-- ============================================================================
-- Purpose: Single source of truth for all content changes
-- Checksum-centric architecture for FAQ regeneration detection
-- ============================================================================

CREATE TABLE IF NOT EXISTS content_change_log (
    change_id BIGINT GENERATED ALWAYS AS IDENTITY,

    -- ============================================================================
    -- CORE IDENTITY (Dual Identity Model)
    -- ============================================================================
    -- content_id: WHERE the content lives (physical location in content_repo)
    -- content_checksum: WHAT the content is (logical content identity)
    -- ============================================================================
    content_id BIGINT NOT NULL,
    content_checksum STRING NOT NULL,
    file_name STRING NOT NULL,

    -- ============================================================================
    -- DETECTION RESULT (Binary Decision)
    -- ============================================================================
    -- Simple binary question: "Should we regenerate FAQ for this checksum?"
    --   true = Checksum NOT in baseline → Regenerate FAQ (new/modified content)
    --   false = Checksum IN baseline → Reuse existing FAQ (content unchanged)
    -- ============================================================================
    requires_faq_regeneration BOOLEAN NOT NULL,

    -- ============================================================================
    -- METADATA (Flexible JSON Storage)
    -- ============================================================================
    -- All descriptive/contextual fields stored as JSON for maximum flexibility:
    --   {
    --     "page": 2,              // Optional (NULL for HTML/XML/single-page docs)
    --     "title": "...",
    --     "domain": "HR",
    --     "service": "Policy",
    --     "breadcrumb": "...",
    --     "tags": "leave;sick;medical",
    --     "version": 1,
    --     "orgoid": "ORG001",
    --     "associateoid": "ASSOC001",
    --     ... any other content_repo fields
    --   }
    -- ============================================================================
    metadata STRING COMMENT 'JSON metadata - use get_json_object() or from_json() to query',

    -- ============================================================================
    -- TIMESTAMPS
    -- ============================================================================
    detected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    source_modified_at TIMESTAMP NOT NULL,

    -- ============================================================================
    -- FAQ IMPACT METRICS
    -- ============================================================================
    existing_faq_count INT DEFAULT 0 COMMENT 'How many FAQs exist for this checksum',

    -- ============================================================================
    -- DETECTION CONTEXT (Batch Tracking)
    -- ============================================================================
    detection_run_id STRING COMMENT 'ISO timestamp of detection run (groups batch detections)',
    since_date TIMESTAMP COMMENT 'Detection period start (for audit/debug)'
)
COMMENT 'Content change detection log - checksum-centric FAQ regeneration tracking'
TBLPROPERTIES (
    'delta.enableChangeDataFeed' = 'true',
    'delta.autoOptimize.optimizeWrite' = 'true',
    'delta.autoOptimize.autoCompact' = 'true'
);

-- Add constraints after table creation to avoid SQL Editor parsing issues
ALTER TABLE content_change_log ADD CONSTRAINT pk_content_change_log PRIMARY KEY (change_id);
ALTER TABLE content_change_log ADD CONSTRAINT chk_checksum_length CHECK (LENGTH(content_checksum) = 64);

-- Foreign key constraint (optional - comment out if it causes issues)
-- Note: Foreign keys in Databricks are informational only (not enforced)
-- Uncomment the next line if you want the FK metadata:
-- ALTER TABLE content_change_log ADD CONSTRAINT fk_ccl_content FOREIGN KEY (content_id) REFERENCES content_repo(ud_source_file_id);

-- ============================================================================
-- INDEXES / OPTIMIZATIONS
-- ============================================================================
-- Note: Databricks Delta tables use Z-ordering and partitioning instead of indexes
-- These OPTIMIZE commands should be run periodically, not during table creation

-- For content_repo: Common query patterns
-- Run periodically: OPTIMIZE content_repo ZORDER BY (raw_file_nme, content_checksum, last_modified_dt);

-- For faq_questions: Common query patterns
-- Run periodically: OPTIMIZE faq_questions ZORDER BY (question_txt, domain, service);

-- For faq_answers: Common query patterns
-- Run periodically: OPTIMIZE faq_answers ZORDER BY (question_id, domain, service);

-- For content_change_log: Common query patterns
-- Run periodically: OPTIMIZE content_change_log ZORDER BY (content_checksum, file_name, requires_faq_regeneration, detected_at);

-- ============================================================================
-- REMOVED TABLES
-- ============================================================================
-- REMOVED: content_diffs table (entire table)
-- Reason: Binary decision model doesn't track edit types or previous versions
--
-- REMOVED: faq_content_map table (entire table)
-- Reason: FAQ-to-content mapping handled externally
--
-- REMOVED: schema_version table (entire table)
-- Reason: Schema versioning handled through migration scripts
-- ============================================================================

-- ============================================================================
-- VIEWS (Derived Data and Analytics)
-- ============================================================================
-- Note: Views use Databricks SQL syntax with get_json_object() for JSON extraction
-- ============================================================================

-- ============================================================================
-- VIEW: v_content_detection_summary
-- ============================================================================
-- Purpose: Summary of content detections by file and regeneration requirement
-- ============================================================================

CREATE OR REPLACE VIEW v_content_detection_summary AS
SELECT
    file_name,
    requires_faq_regeneration,
    COUNT(*) as detection_count,
    MIN(source_modified_at) as earliest_modification,
    MAX(source_modified_at) as latest_modification,
    MIN(detected_at) as first_detection,
    MAX(detected_at) as last_detection,
    COUNT(DISTINCT content_checksum) as unique_checksums,
    SUM(existing_faq_count) as total_faqs_affected,
    COUNT(DISTINCT detection_run_id) as detection_runs
FROM content_change_log
GROUP BY file_name, requires_faq_regeneration;

-- ============================================================================
-- VIEW: v_latest_content_checksums
-- ============================================================================
-- Purpose: Latest checksum for each file (with optional page from JSON)
-- ============================================================================

CREATE OR REPLACE VIEW v_latest_content_checksums AS
WITH latest_detections AS (
    SELECT
        content_id,
        file_name,
        get_json_object(metadata, '$.page') as page_number,
        content_checksum,
        requires_faq_regeneration,
        source_modified_at,
        detected_at,
        existing_faq_count,
        metadata,
        ROW_NUMBER() OVER (
            PARTITION BY content_id
            ORDER BY detected_at DESC, change_id DESC
        ) as rn
    FROM content_change_log
)
SELECT
    content_id,
    file_name,
    CAST(page_number AS INT) as page_number,
    content_checksum,
    requires_faq_regeneration,
    source_modified_at as last_modified_at,
    detected_at as last_detected_at,
    existing_faq_count,
    metadata
FROM latest_detections
WHERE rn = 1;

-- ============================================================================
-- VIEW: v_regeneration_queue
-- ============================================================================
-- Purpose: Content requiring FAQ regeneration (processing queue)
-- Ordered by impact (existing FAQ count) and modification time
-- ============================================================================

CREATE OR REPLACE VIEW v_regeneration_queue AS
SELECT
    ccl.change_id,
    ccl.content_id,
    ccl.content_checksum,
    ccl.file_name,
    CAST(get_json_object(ccl.metadata, '$.page') AS INT) as page_number,
    ccl.source_modified_at,
    ccl.detected_at,
    ccl.existing_faq_count,
    ccl.detection_run_id,
    ccl.metadata,
    -- Priority score (higher = more urgent)
    -- Weighted by FAQ impact and recency
    (ccl.existing_faq_count * 100) +
    DATEDIFF(CURRENT_TIMESTAMP(), ccl.source_modified_at) as priority_score
FROM content_change_log ccl
WHERE ccl.requires_faq_regeneration = true
ORDER BY priority_score DESC, ccl.detected_at DESC;

-- ============================================================================
-- VIEW: v_detection_run_stats
-- ============================================================================
-- Purpose: Statistics for each detection run (batch analytics)
-- ============================================================================

CREATE OR REPLACE VIEW v_detection_run_stats AS
SELECT
    detection_run_id,
    MIN(detected_at) as run_started_at,
    MAX(detected_at) as run_completed_at,
    COUNT(*) as total_pages_analyzed,
    SUM(CASE WHEN requires_faq_regeneration = true THEN 1 ELSE 0 END) as pages_requiring_regeneration,
    SUM(CASE WHEN requires_faq_regeneration = false THEN 1 ELSE 0 END) as pages_not_requiring_regeneration,
    SUM(existing_faq_count) as total_existing_faqs,
    SUM(CASE WHEN requires_faq_regeneration = true THEN existing_faq_count ELSE 0 END) as faqs_to_invalidate,
    COUNT(DISTINCT file_name) as files_processed,
    COUNT(DISTINCT content_checksum) as unique_checksums_detected,
    MIN(since_date) as detection_period_start
FROM content_change_log
WHERE detection_run_id IS NOT NULL
GROUP BY detection_run_id
ORDER BY run_started_at DESC;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================
-- Run these to verify schema was created successfully
-- Note: These are commented out to avoid execution errors in SQL Editor
-- Uncomment and run them individually after the schema is created

-- SELECT '✅ Schema v4 applied successfully to Databricks!' as status;

-- List all tables in current schema
-- SHOW TABLES;

-- Verify specific tables exist
-- DESCRIBE TABLE content_repo;
-- DESCRIBE TABLE faq_questions;
-- DESCRIBE TABLE faq_answers;
-- DESCRIBE TABLE content_change_log;

-- List all views
-- SHOW VIEWS;

-- Check table properties (optional)
-- SHOW TBLPROPERTIES content_repo;
-- SHOW TBLPROPERTIES content_change_log;

-- Test a simple query on each table
-- SELECT COUNT(*) as content_repo_count FROM content_repo;
-- SELECT COUNT(*) as faq_questions_count FROM faq_questions;
-- SELECT COUNT(*) as faq_answers_count FROM faq_answers;
-- SELECT COUNT(*) as content_change_log_count FROM content_change_log;

-- SELECT '✅ Schema deployment complete!' as status;

-- ============================================================================
-- TROUBLESHOOTING SECTION
-- ============================================================================

-- ============================================================================
-- ERROR: "GENERATED ALWAYS AS IDENTITY is not supported"
-- ============================================================================
-- If you get this error, your DBR version is < 10.4
-- Solution: Replace IDENTITY columns with regular BIGINT columns
--
-- Replace this:
--   ud_source_file_id BIGINT GENERATED ALWAYS AS IDENTITY,
--
-- With this:
--   ud_source_file_id BIGINT NOT NULL,
--
-- Then generate IDs in your application code, or use:
--   monotonically_increasing_id() in PySpark
--   or row_number() OVER (ORDER BY created_dt) in SQL
-- ============================================================================

-- ============================================================================
-- ERROR: "Cannot add foreign key constraint"
-- ============================================================================
-- Foreign keys in Databricks are informational only (not enforced)
-- If you get FK errors, the ALTER TABLE FK statements are commented out
-- You can safely skip them - referential integrity must be maintained
-- in your application code
-- ============================================================================

-- ============================================================================
-- ERROR: "CHECK constraint not supported"
-- ============================================================================
-- If CHECK constraints fail, comment out the ALTER TABLE ADD CONSTRAINT chk_* lines
-- Databricks supports CHECK constraints from DBR 9.1+, but some versions have issues
-- Validate data in your application instead
-- ============================================================================

-- ============================================================================
-- ERROR: "Catalog/Schema does not exist"
-- ============================================================================
-- Solution: Create them first
-- CREATE CATALOG IF NOT EXISTS your_catalog_name;
-- CREATE SCHEMA IF NOT EXISTS your_catalog_name.your_schema_name;
-- Then USE CATALOG and USE SCHEMA before running this script
-- ============================================================================

-- ============================================================================
-- ALTERNATIVE: Fallback schema for older DBR versions (< 10.4)
-- ============================================================================
-- If GENERATED ALWAYS AS IDENTITY doesn't work, use this alternative:
--
-- CREATE TABLE IF NOT EXISTS content_repo (
--     ud_source_file_id BIGINT NOT NULL,
--     domain STRING,
--     service STRING,
--     orgoid STRING,
--     associateoid STRING,
--     raw_file_nme STRING NOT NULL,
--     raw_file_type STRING,
--     raw_file_version_nbr INT DEFAULT 1,
--     raw_file_page_nbr INT NOT NULL,
--     source_url_txt STRING,
--     parent_location_txt STRING,
--     raw_file_path STRING,
--     extracted_markdown_file_path STRING,
--     extracted_layout_file_path STRING,
--     title_nme STRING,
--     breadcrumb_txt STRING,
--     content_tags_txt STRING,
--     version_nbr INT DEFAULT 1,
--     content_checksum STRING,
--     file_status STRING,
--     created_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP(),
--     last_modified_dt TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP()
-- )
-- USING DELTA
-- COMMENT 'Source content repository - foundation table for all content tracking'
-- TBLPROPERTIES (
--     'delta.enableChangeDataFeed' = 'true',
--     'delta.autoOptimize.optimizeWrite' = 'true',
--     'delta.autoOptimize.autoCompact' = 'true'
-- );
--
-- Then add constraints:
-- ALTER TABLE content_repo ADD CONSTRAINT pk_content_repo PRIMARY KEY (ud_source_file_id);
--
-- And generate IDs in Python:
-- from pyspark.sql.functions import monotonically_increasing_id
-- df = df.withColumn("ud_source_file_id", monotonically_increasing_id())
-- ============================================================================

-- ============================================================================
-- END OF SCRIPT
-- ============================================================================
--
-- ✅ Schema deployment complete!
--
-- NEXT STEPS:
-- 1. Verify tables were created: SHOW TABLES;
-- 2. Check table schemas: DESCRIBE TABLE content_repo;
-- 3. Run OPTIMIZE with ZORDER BY for performance (see DATABRICKS_DEPLOYMENT_GUIDE.md)
-- 4. Update your Python/PySpark code to use these tables
-- 5. Set up permissions for users and service accounts
-- ============================================================================
