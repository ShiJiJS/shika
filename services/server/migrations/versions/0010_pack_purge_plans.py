"""Persist exact, read-only image deletion previews independently of execution."""

import sqlalchemy as sa
from alembic import op

revision = "0010"
down_revision = "0009"


def upgrade():
    op.create_table(
        "pack_purge_plans",
        sa.Column("historical", sa.Boolean(), nullable=False, server_default="0"),
        sa.Column("id", sa.String(), sa.ForeignKey("tasks.id"), primary_key=True),
        sa.Column("request_key", sa.String(), nullable=False, unique=True),
        sa.Column("request_hash", sa.String(), nullable=False),
        sa.Column("expires_at", sa.Float(), nullable=False),
        sa.Column("digest", sa.String(), nullable=True),
    )
    op.create_table(
        "pack_purge_entries",
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("path", sa.Text(), nullable=False),
        sa.Column("image_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("image_bytes", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("retained_entries", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("plan_id", sa.String(), sa.ForeignKey("pack_purge_plans.id"), nullable=False),
        sa.Column("pack_id", sa.String(), sa.ForeignKey("packs.id"), nullable=False),
        sa.Column("trash_id", sa.String(), sa.ForeignKey("pack_trash_items.id"), nullable=False),
        sa.Column("source", sa.JSON(), nullable=False),
        sa.Column("manifest", sa.JSON(), nullable=True),
        sa.Column("digest", sa.String(), nullable=True),
        sa.Column("error", sa.String(), nullable=True),
        sa.UniqueConstraint("plan_id", "trash_id"),
    )
    op.create_index("ix_pack_purge_entries_plan_id", "pack_purge_entries", ["plan_id"])
    op.create_index("ix_pack_purge_entries_pack_id", "pack_purge_entries", ["pack_id"])


def downgrade():
    op.drop_table("pack_purge_entries")
    op.drop_table("pack_purge_plans")
