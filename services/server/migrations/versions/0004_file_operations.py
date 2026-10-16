"""Durable file intents, per-file checkpoints, trash identity and scan epochs."""

import sqlalchemy as sa
from alembic import op

revision = "0004"
down_revision = "0003"


def upgrade():
    op.add_column(
        "videos", sa.Column("generation", sa.Integer(), nullable=False, server_default="0")
    )
    op.create_table(
        "file_operations",
        sa.Column("id", sa.String(), sa.ForeignKey("tasks.id"), primary_key=True),
        sa.Column("request_key", sa.String(), unique=True, nullable=False),
        sa.Column("request_hash", sa.String(), nullable=False),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("undo_of", sa.String()),
        sa.Column("round_snapshot", sa.JSON(), nullable=False),
        sa.Column("historical", sa.Boolean(), nullable=False),
    )
    op.create_table(
        "file_steps",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("operation_id", sa.String(), sa.ForeignKey("file_operations.id"), nullable=False),
        sa.Column("requested_id", sa.String(), nullable=False),
        sa.Column("video_id", sa.String(), sa.ForeignKey("videos.id")),
        sa.Column("trash_id", sa.String()),
        sa.Column("original_status", sa.String(), nullable=False),
        sa.Column("root_path", sa.Text(), nullable=False),
        sa.Column("original_path", sa.Text(), nullable=False),
        sa.Column("source", sa.Text(), nullable=False),
        sa.Column("destination", sa.Text(), nullable=False),
        sa.Column("staging", sa.Text(), nullable=False),
        sa.Column("copy_path", sa.Text(), nullable=False),
        sa.Column("expected_hash", sa.String(), nullable=False),
        sa.Column("expected_size", sa.Integer(), nullable=False),
        sa.Column("source_signature", sa.JSON(), nullable=False),
        sa.Column("claimed_identity", sa.JSON(), nullable=False),
        sa.Column("published_identity", sa.JSON(), nullable=False),
        sa.Column("copy_identity", sa.JSON(), nullable=False),
        sa.Column("phase", sa.String(), nullable=False),
        sa.Column("outcome", sa.String(), nullable=False),
        sa.Column("error", sa.String()),
    )
    for field in ("operation_id", "video_id", "phase"):
        op.create_index(f"ix_file_steps_{field}", "file_steps", [field])
    op.create_table(
        "trash_items",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("video_id", sa.String(), sa.ForeignKey("videos.id"), nullable=False),
        sa.Column("operation_id", sa.String(), sa.ForeignKey("file_operations.id"), nullable=False),
        sa.Column("root_path", sa.Text(), nullable=False),
        sa.Column("original_path", sa.Text(), nullable=False),
        sa.Column("trash_path", sa.Text(), nullable=False),
        sa.Column("sha256", sa.String(), nullable=False),
        sa.Column("size", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(), nullable=False),
        sa.Column("deleted_at", sa.Float(), nullable=False),
    )
    op.create_index("ix_trash_items_video_id", "trash_items", ["video_id"])
    op.create_index("ix_trash_items_status", "trash_items", ["status"])
    op.create_index(
        "trash_active_video",
        "trash_items",
        ["video_id"],
        unique=True,
        sqlite_where=sa.text("status='active'"),
    )


def downgrade():
    op.drop_table("trash_items")
    op.drop_table("file_steps")
    op.drop_table("file_operations")
    op.drop_column("videos", "generation")
