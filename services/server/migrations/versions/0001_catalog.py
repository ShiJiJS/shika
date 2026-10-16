"""Catalog, authentication and durable scan jobs."""

import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None


def upgrade():
    op.create_table(
        "settings",
        sa.Column("key", sa.String(), primary_key=True),
        sa.Column("value", sa.Text(), nullable=False),
    )
    op.create_table(
        "access_tokens",
        sa.Column("digest", sa.String(), primary_key=True),
        sa.Column("expires_at", sa.Float(), nullable=False),
    )
    op.create_table(
        "roots",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("path", sa.Text(), nullable=False, unique=True),
        sa.Column("mount_id", sa.String(), nullable=False),
        sa.Column("available", sa.Boolean(), nullable=False),
        sa.Column("error", sa.String()),
        sa.Column("last_scan", sa.Float()),
    )
    op.create_table(
        "directories",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("root_id", sa.String(), sa.ForeignKey("roots.id"), nullable=False),
        sa.Column("path", sa.Text(), nullable=False, unique=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("seen_scan", sa.String()),
    )
    op.create_index("ix_directories_root_id", "directories", ["root_id"])
    op.create_table(
        "videos",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("root_id", sa.String(), sa.ForeignKey("roots.id"), nullable=False),
        sa.Column("path", sa.Text(), nullable=False),
        sa.Column("location_key", sa.Text(), unique=True),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("error", sa.String()),
        sa.Column("size", sa.Integer(), nullable=False),
        sa.Column("device", sa.String(), nullable=False),
        sa.Column("inode", sa.String(), nullable=False),
        sa.Column("mtime_ns", sa.String(), nullable=False),
        sa.Column("ctime_ns", sa.String(), nullable=False),
        sa.Column("sha256", sa.String(), nullable=False),
        sa.Column("quick_hash", sa.String(), nullable=False),
        sa.Column("duration", sa.Float(), nullable=False),
        sa.Column("width", sa.Integer(), nullable=False),
        sa.Column("height", sa.Integer(), nullable=False),
        sa.Column("rotation", sa.Integer(), nullable=False),
        sa.Column("type", sa.String(), nullable=False),
        sa.Column("video_codec", sa.String(), nullable=False),
        sa.Column("audio_codec", sa.String()),
        sa.Column("container", sa.String(), nullable=False),
        sa.Column("thumbnail", sa.String()),
        sa.Column("seen_scan", sa.String(), nullable=False),
        sa.Column("created_at", sa.Float(), nullable=False),
    )
    for column in ("root_id", "path", "status", "sha256", "quick_hash"):
        op.create_index(f"ix_videos_{column}", "videos", [column])
    op.create_index("videos_order", "videos", ["path", "id"])
    op.create_table(
        "observations",
        sa.Column("path", sa.Text(), primary_key=True),
        sa.Column("signature", sa.JSON(), nullable=False),
        sa.Column("stable_since", sa.Float(), nullable=False),
    )
    op.create_table(
        "tasks",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("phase", sa.String(), nullable=False),
        sa.Column("created_at", sa.Float(), nullable=False),
        sa.Column("finished_at", sa.Float()),
        sa.Column("result", sa.JSON(), nullable=False),
        sa.Column("error", sa.String()),
    )
    op.create_index("ix_tasks_status", "tasks", ["status"])


def downgrade():
    for table in (
        "tasks",
        "observations",
        "videos",
        "directories",
        "roots",
        "access_tokens",
        "settings",
    ):
        op.drop_table(table)
