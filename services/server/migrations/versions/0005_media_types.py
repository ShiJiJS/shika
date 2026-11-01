"""Typed media roots and independently managed image packs (SQLite)."""

from alembic import op

revision = "0005"
down_revision = "0004"

# Static SQL, generated once from the LF1 model; never import future models here.
TABLE_DDL = [
    """CREATE TABLE pack_sessions (
    id VARCHAR NOT NULL,
    request_id VARCHAR NOT NULL,
    request_hash VARCHAR NOT NULL,
    scope JSON NOT NULL,
    source JSON NOT NULL,
    "order" VARCHAR NOT NULL,
    cursor INTEGER NOT NULL,
    revision INTEGER NOT NULL,
    finished BOOLEAN NOT NULL,
    candidate_count INTEGER NOT NULL,
    created_at FLOAT NOT NULL,
    PRIMARY KEY (id),
    CHECK (cursor >= 0 AND revision >= 0 AND candidate_count >= 0),
    CHECK ("order" IN ('random','sequential')),
    UNIQUE (request_id)
)""",
    """CREATE TABLE pack_tag_definitions (
    id VARCHAR NOT NULL,
    name VARCHAR NOT NULL,
    created_at FLOAT NOT NULL,
    PRIMARY KEY (id),
    UNIQUE (name)
)""",
    """CREATE TABLE pack_file_operations (
    id VARCHAR NOT NULL,
    request_key VARCHAR NOT NULL,
    request_hash VARCHAR NOT NULL,
    kind VARCHAR NOT NULL,
    undo_of VARCHAR,
    session_snapshot JSON NOT NULL,
    historical BOOLEAN NOT NULL,
    PRIMARY KEY (id),
    CHECK (kind IN ('trash','restore','permanent','undo')),
    FOREIGN KEY(id) REFERENCES tasks (id),
    UNIQUE (request_key),
    FOREIGN KEY(undo_of) REFERENCES pack_file_operations (id)
)""",
    """CREATE TABLE packs (
    id VARCHAR NOT NULL,
    root_id VARCHAR NOT NULL,
    path TEXT NOT NULL,
    location_key TEXT,
    name VARCHAR NOT NULL,
    status VARCHAR NOT NULL,
    error VARCHAR,
    device VARCHAR NOT NULL,
    inode VARCHAR NOT NULL,
    content_version INTEGER NOT NULL,
    page_count INTEGER NOT NULL,
    generation INTEGER NOT NULL,
    seen_scan VARCHAR,
    created_at FLOAT NOT NULL,
    PRIMARY KEY (id),
    CHECK (content_version >= 0 AND page_count >= 0),
    FOREIGN KEY(root_id) REFERENCES roots (id),
    UNIQUE (location_key)
)""",
    """CREATE TABLE pack_pages (
    id VARCHAR NOT NULL,
    pack_id VARCHAR NOT NULL,
    path TEXT NOT NULL,
    relative_path TEXT NOT NULL,
    ordinal INTEGER NOT NULL,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    size INTEGER NOT NULL,
    format VARCHAR NOT NULL,
    signature JSON NOT NULL,
    sha256 VARCHAR,
    error VARCHAR,
    thumbnail VARCHAR,
    seen_scan VARCHAR,
    PRIMARY KEY (id),
    UNIQUE (pack_id, id),
    UNIQUE (pack_id, relative_path),
    CHECK (ordinal >= 0 AND width >= 0 AND height >= 0 AND size >= 0),
    FOREIGN KEY(pack_id) REFERENCES packs (id) ON DELETE CASCADE
)""",
    """CREATE TABLE pack_preferences (
    pack_id VARCHAR NOT NULL,
    mode VARCHAR NOT NULL,
    direction VARCHAR NOT NULL,
    gap BOOLEAN NOT NULL,
    fit VARCHAR NOT NULL,
    PRIMARY KEY (pack_id),
    CHECK (mode IN ('horizontal','vertical')),
    CHECK (direction IN ('ltr','rtl')),
    CHECK (fit IN ('contain','width')),
    FOREIGN KEY(pack_id) REFERENCES packs (id) ON DELETE CASCADE
)""",
    """CREATE TABLE pack_session_entries (
    session_id VARCHAR NOT NULL,
    ordinal INTEGER NOT NULL,
    pack_id VARCHAR NOT NULL,
    PRIMARY KEY (session_id, ordinal),
    UNIQUE (session_id, pack_id),
    FOREIGN KEY(session_id) REFERENCES pack_sessions (id) ON DELETE CASCADE,
    FOREIGN KEY(pack_id) REFERENCES packs (id)
)""",
    """CREATE TABLE pack_tag_links (
    pack_id VARCHAR NOT NULL,
    tag_id VARCHAR NOT NULL,
    PRIMARY KEY (pack_id, tag_id),
    FOREIGN KEY(pack_id) REFERENCES packs (id) ON DELETE CASCADE,
    FOREIGN KEY(tag_id) REFERENCES pack_tag_definitions (id) ON DELETE CASCADE
)""",
    """CREATE TABLE pack_trash_items (
    id VARCHAR NOT NULL,
    pack_id VARCHAR NOT NULL,
    operation_id VARCHAR NOT NULL,
    root_path TEXT NOT NULL,
    original_path TEXT NOT NULL,
    manifest JSON NOT NULL,
    status VARCHAR NOT NULL,
    deleted_at FLOAT NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY(pack_id) REFERENCES packs (id),
    FOREIGN KEY(operation_id) REFERENCES pack_file_operations (id)
)""",
    """CREATE TABLE recent_entries (
    id VARCHAR NOT NULL,
    kind VARCHAR NOT NULL,
    video_id VARCHAR,
    pack_id VARCHAR,
    opened_at FLOAT NOT NULL,
    PRIMARY KEY (id),
    CHECK ((kind='video' AND video_id IS NOT NULL AND pack_id IS NULL) OR (kind='pack' AND pack_id IS NOT NULL AND video_id IS NULL)),
    UNIQUE (video_id),
    FOREIGN KEY(video_id) REFERENCES videos (id) ON DELETE CASCADE,
    UNIQUE (pack_id),
    FOREIGN KEY(pack_id) REFERENCES packs (id) ON DELETE CASCADE
)""",
    """CREATE TABLE pack_file_steps (
    id VARCHAR NOT NULL,
    operation_id VARCHAR NOT NULL,
    pack_id VARCHAR NOT NULL,
    page_id VARCHAR,
    requested_id VARCHAR NOT NULL,
    root_path TEXT NOT NULL,
    original_path TEXT NOT NULL,
    source_signature JSON NOT NULL,
    expected_hash VARCHAR,
    expected_size INTEGER NOT NULL,
    phase VARCHAR NOT NULL,
    outcome VARCHAR NOT NULL,
    error VARCHAR,
    PRIMARY KEY (id),
    FOREIGN KEY(operation_id) REFERENCES pack_file_operations (id),
    FOREIGN KEY(pack_id) REFERENCES packs (id),
    FOREIGN KEY(page_id) REFERENCES pack_pages (id)
)""",
    """CREATE TABLE pack_progress (
    pack_id VARCHAR NOT NULL,
    page_id VARCHAR,
    offset_ratio FLOAT NOT NULL,
    completed BOOLEAN NOT NULL,
    revision INTEGER NOT NULL,
    updated_at FLOAT NOT NULL,
    PRIMARY KEY (pack_id),
    FOREIGN KEY(pack_id, page_id) REFERENCES pack_pages (pack_id, id),
    CHECK (offset_ratio >= 0 AND offset_ratio <= 1 AND revision >= 0),
    FOREIGN KEY(pack_id) REFERENCES packs (id) ON DELETE CASCADE
)""",
]
INDEX_DDL = [
    "CREATE INDEX ix_packs_path ON packs (path)",
    "CREATE INDEX ix_pack_pages_path ON pack_pages (path)",
    "CREATE INDEX ix_packs_root_id ON packs (root_id)",
    "CREATE INDEX ix_packs_status ON packs (status)",
    "CREATE INDEX ix_pack_pages_pack_id ON pack_pages (pack_id)",
    "CREATE INDEX pack_pages_order ON pack_pages (pack_id, ordinal, id)",
    "CREATE INDEX ix_pack_session_entries_pack_id ON pack_session_entries (pack_id)",
    "CREATE INDEX pack_tags_tag_pack ON pack_tag_links (tag_id, pack_id)",
    "CREATE INDEX ix_pack_trash_items_pack_id ON pack_trash_items (pack_id)",
    "CREATE INDEX ix_pack_trash_items_status ON pack_trash_items (status)",
    "CREATE UNIQUE INDEX pack_trash_active ON pack_trash_items (pack_id) WHERE status='active'",
    "CREATE INDEX ix_recent_entries_opened_at ON recent_entries (opened_at)",
    "CREATE INDEX ix_pack_file_steps_operation_id ON pack_file_steps (operation_id)",
    "CREATE INDEX ix_pack_file_steps_pack_id ON pack_file_steps (pack_id)",
    "CREATE INDEX ix_pack_file_steps_phase ON pack_file_steps (phase)",
]


def upgrade():
    op.execute(
        "ALTER TABLE roots ADD COLUMN kind VARCHAR NOT NULL DEFAULT 'video' CHECK (kind IN ('video','pack'))"
    )
    op.execute(
        "ALTER TABLE roots ADD COLUMN enabled BOOLEAN NOT NULL DEFAULT 1 CHECK (enabled IN (0,1))"
    )
    for statement in TABLE_DDL + INDEX_DDL:
        op.execute(statement)


def downgrade():
    op.drop_table("pack_progress")
    op.drop_table("pack_file_steps")
    op.drop_table("recent_entries")
    op.drop_table("pack_trash_items")
    op.drop_table("pack_tag_links")
    op.drop_table("pack_session_entries")
    op.drop_table("pack_preferences")
    op.drop_table("pack_pages")
    op.drop_table("packs")
    op.drop_table("pack_file_operations")
    op.drop_table("pack_tag_definitions")
    op.drop_table("pack_sessions")
    op.drop_column("roots", "enabled")
    op.drop_column("roots", "kind")
