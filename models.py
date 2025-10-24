"""
Data models for granular impact analysis V8.2.

Defines dataclass models matching the production database schema:
- Content checksums (master content table)
- FAQ questions and answers (separated)
- FAQ provenance tracking (question/answer sources with temporal validity)
- Content change detection
- Content diffs (NEW in V8 - granular diff analysis)
- FAQ impact analysis (NEW in V8 - selective invalidation)
- Audit logs

This module provides Python dataclasses that map to the V8.2 database schema
for granular FAQ impact analysis.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional


# ============================================================================
# ENUMS
# ============================================================================


class ContentStatus(str, Enum):
    """Content status values."""

    ACTIVE = "active"
    ARCHIVED = "archived"
    DELETED = "deleted"


class FAQStatus(str, Enum):
    """FAQ status values."""

    ACTIVE = "active"
    INVALIDATED = "invalidated"
    ARCHIVED = "archived"
    DELETED = "deleted"


class SourceType(str, Enum):
    """FAQ source types."""

    FROM_DOCUMENTS = "from_documents"
    FROM_USER_QUERIES = "from_user_queries"
    FROM_MANUAL = "from_manual"
    FROM_VALIDATION = "from_validation"


class GenerationMethod(str, Enum):
    """FAQ generation methods."""

    LLM_GENERATED = "llm_generated"
    HUMAN_WRITTEN = "human_written"
    EXTRACTED = "extracted"


class ChangeType(str, Enum):
    """Content change types."""

    NEW_CONTENT = "new_content"
    MODIFIED_CONTENT = "modified_content"
    UNCHANGED_CONTENT = "unchanged_content"
    DELETED_CONTENT = "deleted_content"
    LOCATION_CHANGE = "location_change"


class InvalidationReason(str, Enum):
    """Provenance invalidation reasons."""

    CONTENT_CHANGED = "content_changed"
    CONTENT_DELETED = "content_deleted"
    QUALITY_ISSUE = "quality_issue"
    MANUAL = "manual"
    SELECTIVE_IMPACT = "selective_impact"


class DiffType(str, Enum):
    """Diff types."""

    UNIFIED = "unified"
    WORD_DIFF = "word_diff"
    SEMANTIC_CHUNKS = "semantic_chunks"


class DiffAlgorithm(str, Enum):
    """Diff algorithms."""

    MYERS = "myers"
    PATIENCE = "patience"
    HISTOGRAM = "histogram"


class ImpactLevel(str, Enum):
    """Impact severity levels."""

    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    NONE = "none"


class AnalysisMethod(str, Enum):
    """Impact analysis methods."""

    RULE_BASED = "rule_based"
    ML_MODEL = "ml_model"
    HYBRID = "hybrid"


class AuditAction(str, Enum):
    """Audit log action types."""

    INSERT = "INSERT"
    UPDATE = "UPDATE"
    DELETE = "DELETE"
    INVALIDATE = "INVALIDATE"
    RESTORE = "RESTORE"
    SELECTIVE_INVALIDATE = "SELECTIVE_INVALIDATE"


class AnswerFormat(str, Enum):
    """Answer text formats."""

    HTML = "html"
    MARKDOWN = "markdown"
    PLAIN = "plain"


# ============================================================================
# CORE TABLES (from V7)
# ============================================================================


@dataclass
class ContentChecksum:
    """
    Represents a unique content identity (master content table).

    Maps to: content_checksums table

    The content_checksum is THE identity. Location metadata (file_name,
    page_number, etc.) is for human reference only, NOT for content analysis.
    """

    content_checksum: str  # SHA-256 hash (64 chars) - THE identity
    status: ContentStatus = ContentStatus.ACTIVE
    created_at: datetime = field(default_factory=datetime.now)

    # Content Properties
    file_type: Optional[str] = None  # pdf, html, docx, xml, confluence
    content_format: Optional[str] = None  # markdown, html, plain_text
    title: Optional[str] = None
    word_count: Optional[int] = None
    char_count: Optional[int] = None
    domain: Optional[str] = None  # HR, IT, Finance
    service: Optional[str] = None  # Policy, Benefits, Payroll

    # METADATA: Location information (for human reference only)
    file_name: Optional[str] = None
    page_number: Optional[int] = None
    section_name: Optional[str] = None
    url: Optional[str] = None
    breadcrumb: Optional[str] = None
    source_file_path: Optional[str] = None
    file_version: Optional[str] = None

    # Content Storage
    markdown_file_path: Optional[str] = None
    content_text: Optional[str] = None

    def __post_init__(self):
        """Validate checksum length."""
        if len(self.content_checksum) != 64:
            raise ValueError(f"content_checksum must be 64 chars, got {len(self.content_checksum)}")

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for DataFrame."""
        return {
            "content_checksum": self.content_checksum,
            "file_type": self.file_type,
            "content_format": self.content_format,
            "title": self.title,
            "word_count": self.word_count,
            "char_count": self.char_count,
            "domain": self.domain,
            "service": self.service,
            "status": self.status.value,
            "file_name": self.file_name,
            "page_number": self.page_number,
            "section_name": self.section_name,
            "url": self.url,
            "breadcrumb": self.breadcrumb,
            "source_file_path": self.source_file_path,
            "file_version": self.file_version,
            "markdown_file_path": self.markdown_file_path,
            "content_text": self.content_text,
            "created_at": self.created_at,
        }


@dataclass
class FAQQuestion:
    """
    Represents an FAQ question (content-agnostic).

    Maps to: faq_questions table
    """

    question_id: Optional[int] = None  # IDENTITY column, assigned by DB
    question_text: str = ""
    status: FAQStatus = FAQStatus.ACTIVE
    created_at: datetime = field(default_factory=datetime.now)
    modified_at: datetime = field(default_factory=datetime.now)

    # Metadata
    source_type: Optional[SourceType] = None
    generation_method: Optional[GenerationMethod] = None
    domain: Optional[str] = None
    service: Optional[str] = None
    created_by: str = "system"
    modified_by: str = "system"

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for DataFrame."""
        return {
            "question_id": self.question_id,
            "question_text": self.question_text,
            "source_type": self.source_type.value if self.source_type else None,
            "generation_method": self.generation_method.value if self.generation_method else None,
            "domain": self.domain,
            "service": self.service,
            "status": self.status.value,
            "created_at": self.created_at,
            "modified_at": self.modified_at,
            "created_by": self.created_by,
            "modified_by": self.modified_by,
        }


@dataclass
class FAQQuestionSource:
    """
    Question provenance - which content inspired each question.

    Maps to: faq_question_sources table

    Supports temporal validity:
    - is_valid: Current validity status
    - valid_from/valid_until: Validity time range
    - invalidation_reason: Why it was invalidated
    - invalidated_by_change_id: Which content change caused invalidation
    """

    question_id: int
    content_checksum: str
    is_valid: bool = True
    valid_from: datetime = field(default_factory=datetime.now)
    created_at: datetime = field(default_factory=datetime.now)

    source_id: Optional[int] = None  # IDENTITY column
    is_primary_source: bool = False
    contribution_weight: Optional[float] = None  # 0.0 to 1.0
    valid_until: Optional[datetime] = None
    invalidation_reason: Optional[InvalidationReason] = None
    invalidated_by_change_id: Optional[int] = None

    def __post_init__(self):
        """Validate contribution weight."""
        if self.contribution_weight is not None:
            if not (0.0 <= self.contribution_weight <= 1.0):
                raise ValueError(f"contribution_weight must be 0.0-1.0, got {self.contribution_weight}")

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for DataFrame."""
        return {
            "source_id": self.source_id,
            "question_id": self.question_id,
            "content_checksum": self.content_checksum,
            "is_primary_source": self.is_primary_source,
            "contribution_weight": self.contribution_weight,
            "is_valid": self.is_valid,
            "valid_from": self.valid_from,
            "valid_until": self.valid_until,
            "invalidation_reason": self.invalidation_reason.value if self.invalidation_reason else None,
            "invalidated_by_change_id": self.invalidated_by_change_id,
            "created_at": self.created_at,
        }


@dataclass
class FAQAnswer:
    """
    Represents an FAQ answer (linked to question 1:1).

    Maps to: faq_answers table
    """

    question_id: int
    answer_text: str
    status: FAQStatus = FAQStatus.ACTIVE
    created_at: datetime = field(default_factory=datetime.now)
    modified_at: datetime = field(default_factory=datetime.now)

    answer_id: Optional[int] = None  # IDENTITY column
    answer_format: AnswerFormat = AnswerFormat.HTML
    confidence_score: Optional[float] = None  # 0.0 to 1.0
    created_by: str = "system"
    modified_by: str = "system"

    def __post_init__(self):
        """Validate confidence score."""
        if self.confidence_score is not None:
            if not (0.0 <= self.confidence_score <= 1.0):
                raise ValueError(f"confidence_score must be 0.0-1.0, got {self.confidence_score}")

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for DataFrame."""
        return {
            "answer_id": self.answer_id,
            "question_id": self.question_id,
            "answer_text": self.answer_text,
            "answer_format": self.answer_format.value,
            "confidence_score": self.confidence_score,
            "status": self.status.value,
            "created_at": self.created_at,
            "modified_at": self.modified_at,
            "created_by": self.created_by,
            "modified_by": self.modified_by,
        }


@dataclass
class FAQAnswerSource:
    """
    Answer provenance - which content provided answer information.

    Maps to: faq_answer_sources table

    Supports temporal validity similar to FAQQuestionSource.
    """

    answer_id: int
    content_checksum: str
    is_valid: bool = True
    valid_from: datetime = field(default_factory=datetime.now)
    created_at: datetime = field(default_factory=datetime.now)

    source_id: Optional[int] = None  # IDENTITY column
    is_primary_source: bool = False
    contribution_weight: Optional[float] = None  # 0.0 to 1.0
    context_employed: Optional[str] = None  # JSON: which sections/paragraphs used
    valid_until: Optional[datetime] = None
    invalidation_reason: Optional[InvalidationReason] = None
    invalidated_by_change_id: Optional[int] = None

    def __post_init__(self):
        """Validate contribution weight."""
        if self.contribution_weight is not None:
            if not (0.0 <= self.contribution_weight <= 1.0):
                raise ValueError(f"contribution_weight must be 0.0-1.0, got {self.contribution_weight}")

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for DataFrame."""
        return {
            "source_id": self.source_id,
            "answer_id": self.answer_id,
            "content_checksum": self.content_checksum,
            "is_primary_source": self.is_primary_source,
            "contribution_weight": self.contribution_weight,
            "context_employed": self.context_employed,
            "is_valid": self.is_valid,
            "valid_from": self.valid_from,
            "valid_until": self.valid_until,
            "invalidation_reason": self.invalidation_reason.value if self.invalidation_reason else None,
            "invalidated_by_change_id": self.invalidated_by_change_id,
            "created_at": self.created_at,
        }


@dataclass
class ContentChangeLog:
    """
    Content change detection log with granular impact analysis.

    Maps to: content_change_log table

    NEW in V8: Tracks similarity scores and granular impact counts
    (affected_question_count, affected_answer_count) instead of blanket invalidation.
    """

    content_checksum: str  # NEW checksum
    file_name: str
    requires_faq_regeneration: bool
    detection_run_id: str
    detection_timestamp: datetime = field(default_factory=datetime.now)
    total_faqs_at_risk: int = 0  # Total FAQs linked to old checksum
    affected_question_count: int = 0  # Questions actually affected (V8)
    affected_answer_count: int = 0  # Answers actually affected (V8)

    change_id: Optional[int] = None  # IDENTITY column
    previous_checksum: Optional[str] = None  # NULL for new content
    page_number: Optional[int] = None
    section_name: Optional[str] = None
    change_type: Optional[ChangeType] = None
    similarity_score: Optional[float] = None  # NEW in V8: 0.0 to 1.0
    similarity_method: Optional[str] = None  # bm25, jaccard, cosine, levenshtein
    detection_period_start: Optional[datetime] = None
    source_modified_at: Optional[datetime] = None
    domain: Optional[str] = None
    service: Optional[str] = None

    def __post_init__(self):
        """Validate checksums and similarity score."""
        if len(self.content_checksum) != 64:
            raise ValueError(f"content_checksum must be 64 chars, got {len(self.content_checksum)}")
        if self.previous_checksum and len(self.previous_checksum) != 64:
            raise ValueError(f"previous_checksum must be 64 chars, got {len(self.previous_checksum)}")
        if self.similarity_score is not None:
            if not (0.0 <= self.similarity_score <= 1.0):
                raise ValueError(f"similarity_score must be 0.0-1.0, got {self.similarity_score}")

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for DataFrame."""
        return {
            "change_id": self.change_id,
            "content_checksum": self.content_checksum,
            "previous_checksum": self.previous_checksum,
            "file_name": self.file_name,
            "page_number": self.page_number,
            "section_name": self.section_name,
            "requires_faq_regeneration": self.requires_faq_regeneration,
            "change_type": self.change_type.value if self.change_type else None,
            "similarity_score": self.similarity_score,
            "similarity_method": self.similarity_method,
            "total_faqs_at_risk": self.total_faqs_at_risk,
            "affected_question_count": self.affected_question_count,
            "affected_answer_count": self.affected_answer_count,
            "detection_run_id": self.detection_run_id,
            "detection_timestamp": self.detection_timestamp,
            "detection_period_start": self.detection_period_start,
            "source_modified_at": self.source_modified_at,
            "domain": self.domain,
            "service": self.service,
        }


# ============================================================================
# V8 NEW TABLES (Granular Impact Analysis)
# ============================================================================


@dataclass
class ContentDiff:
    """
    Granular content diffs - tracks WHAT changed between content versions.

    Maps to: content_diffs table (NEW in V8)

    Stores structured diff data including:
    - Diff statistics (additions, deletions, modifications)
    - Semantic change indicators (numeric, date, policy changes)
    - Changed phrases for FAQ matching
    """

    change_id: int
    old_checksum: str
    new_checksum: str
    computed_at: datetime = field(default_factory=datetime.now)

    diff_id: Optional[int] = None  # IDENTITY column
    diff_type: Optional[DiffType] = None
    diff_algorithm: Optional[DiffAlgorithm] = None

    # Diff Statistics
    additions_count: Optional[int] = None
    deletions_count: Optional[int] = None
    modifications_count: Optional[int] = None
    total_changes: Optional[int] = None
    change_percentage: Optional[float] = None  # 0.0 to 100.0

    # Diff Content (JSON)
    diff_data: Optional[str] = None  # JSON with chunks, line numbers, old/new text

    # Semantic Change Indicators
    contains_numeric_changes: Optional[bool] = None
    contains_date_changes: Optional[bool] = None
    contains_policy_changes: Optional[bool] = None
    contains_eligibility_changes: Optional[bool] = None

    # Key phrases that changed (JSON array)
    changed_phrases: Optional[str] = None  # JSON: ["10 sick days", "per year"]

    def __post_init__(self):
        """Validate change percentage."""
        if self.change_percentage is not None:
            if not (0.0 <= self.change_percentage <= 100.0):
                raise ValueError(f"change_percentage must be 0.0-100.0, got {self.change_percentage}")

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for DataFrame."""
        return {
            "diff_id": self.diff_id,
            "change_id": self.change_id,
            "old_checksum": self.old_checksum,
            "new_checksum": self.new_checksum,
            "diff_type": self.diff_type.value if self.diff_type else None,
            "diff_algorithm": self.diff_algorithm.value if self.diff_algorithm else None,
            "additions_count": self.additions_count,
            "deletions_count": self.deletions_count,
            "modifications_count": self.modifications_count,
            "total_changes": self.total_changes,
            "change_percentage": self.change_percentage,
            "diff_data": self.diff_data,
            "contains_numeric_changes": self.contains_numeric_changes,
            "contains_date_changes": self.contains_date_changes,
            "contains_policy_changes": self.contains_policy_changes,
            "contains_eligibility_changes": self.contains_eligibility_changes,
            "changed_phrases": self.changed_phrases,
            "computed_at": self.computed_at,
        }


@dataclass
class FAQImpactAnalysis:
    """
    FAQ-level impact analysis - determines which FAQs affected by content changes.

    Maps to: faq_impact_analysis table (NEW in V8)

    This is the core of granular impact analysis:
    - Multiple scoring methods (lexical, semantic, keyword, phrase)
    - Combined overall_impact_score
    - Final decision: is_affected (True/False)
    - Explainability: impact_reason and matched_changes
    """

    change_id: int
    question_id: int
    overall_impact_score: float  # 0.0 to 1.0
    is_affected: bool
    analyzed_at: datetime = field(default_factory=datetime.now)

    impact_id: Optional[int] = None  # IDENTITY column
    diff_id: Optional[int] = None
    answer_id: Optional[int] = None

    # Individual scoring methods
    lexical_overlap_score: Optional[float] = None  # Jaccard
    semantic_similarity_score: Optional[float] = None  # Cosine
    keyword_match_score: Optional[float] = None
    phrase_match_score: Optional[float] = None

    # Impact Decision
    impact_level: Optional[ImpactLevel] = None
    confidence: Optional[float] = None  # 0.0 to 1.0

    # Explainability
    impact_reason: Optional[str] = None
    matched_changes: Optional[str] = None  # JSON: which specific changes

    # Processing Metadata
    analysis_method: Optional[AnalysisMethod] = None
    analysis_version: Optional[str] = None

    def __post_init__(self):
        """Validate scores."""
        if not (0.0 <= self.overall_impact_score <= 1.0):
            raise ValueError(f"overall_impact_score must be 0.0-1.0, got {self.overall_impact_score}")
        if self.confidence is not None:
            if not (0.0 <= self.confidence <= 1.0):
                raise ValueError(f"confidence must be 0.0-1.0, got {self.confidence}")

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for DataFrame."""
        return {
            "impact_id": self.impact_id,
            "change_id": self.change_id,
            "diff_id": self.diff_id,
            "question_id": self.question_id,
            "answer_id": self.answer_id,
            "overall_impact_score": self.overall_impact_score,
            "lexical_overlap_score": self.lexical_overlap_score,
            "semantic_similarity_score": self.semantic_similarity_score,
            "keyword_match_score": self.keyword_match_score,
            "phrase_match_score": self.phrase_match_score,
            "is_affected": self.is_affected,
            "impact_level": self.impact_level.value if self.impact_level else None,
            "confidence": self.confidence,
            "impact_reason": self.impact_reason,
            "matched_changes": self.matched_changes,
            "analysis_method": self.analysis_method.value if self.analysis_method else None,
            "analysis_version": self.analysis_version,
            "analyzed_at": self.analyzed_at,
        }


@dataclass
class AuditLogEntry:
    """
    Complete audit trail for all FAQ operations.

    Maps to: faq_audit_log table
    """

    table_name: str
    action: AuditAction
    performed_by: str = "system"
    performed_at: datetime = field(default_factory=datetime.now)

    audit_id: Optional[int] = None  # IDENTITY column
    record_id: Optional[int] = None
    content_checksum: Optional[str] = None
    old_values: Optional[str] = None  # JSON snapshot before change
    new_values: Optional[str] = None  # JSON snapshot after change
    detection_run_id: Optional[str] = None
    change_reason: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for DataFrame."""
        return {
            "audit_id": self.audit_id,
            "table_name": self.table_name,
            "record_id": self.record_id,
            "content_checksum": self.content_checksum,
            "action": self.action.value,
            "old_values": self.old_values,
            "new_values": self.new_values,
            "detection_run_id": self.detection_run_id,
            "change_reason": self.change_reason,
            "performed_by": self.performed_by,
            "performed_at": self.performed_at,
        }


# ============================================================================
# HELPER MODELS (not directly mapped to tables)
# ============================================================================


@dataclass
class ContentChange:
    """
    Represents a detected change in content (used during change detection phase).

    This is a transient model used before persisting to ContentChangeLog.
    """

    content_checksum: str  # NEW checksum
    old_checksum: str
    new_checksum: str
    change_type: ChangeType
    detected_at: datetime = field(default_factory=datetime.now)

    file_name: Optional[str] = None
    page_number: Optional[int] = None
    old_content: Optional[str] = None
    new_content: Optional[str] = None
    similarity_score: Optional[float] = None
    llm_friendly_diff: Optional[str] = None  # LLM-friendly diff for MODIFIED content

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "content_checksum": self.content_checksum,
            "old_checksum": self.old_checksum,
            "new_checksum": self.new_checksum,
            "change_type": self.change_type.value,
            "detected_at": self.detected_at,
            "file_name": self.file_name,
            "page_number": self.page_number,
            "old_content": self.old_content,
            "new_content": self.new_content,
            "similarity_score": self.similarity_score,
            "llm_friendly_diff": self.llm_friendly_diff,
        }
