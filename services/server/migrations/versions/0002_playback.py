"""Durable playback rounds and immutable candidate order."""

import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"


def upgrade():
    op.create_table(
        "playback_rounds",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("request_id", sa.String(), nullable=False, unique=True),
        sa.Column("request_hash", sa.String(), nullable=False),
        sa.Column("order", sa.String(), nullable=False),
        sa.Column("scope", sa.JSON(), nullable=False),
        sa.Column("cursor", sa.Integer(), nullable=False),
        sa.Column("revision", sa.Integer(), nullable=False),
        sa.Column("finished", sa.Boolean(), nullable=False),
        sa.Column("candidate_count", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.Float(), nullable=False),
    )
    op.create_table(
        "round_entries",
        sa.Column(
            "round_id",
            sa.String(),
            sa.ForeignKey("playback_rounds.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("ordinal", sa.Integer(), primary_key=True),
        sa.Column("video_id", sa.String(), sa.ForeignKey("videos.id"), nullable=False),
    )
    op.create_index("ix_round_entries_video_id", "round_entries", ["video_id"])


def downgrade():
    op.drop_table("round_entries")
    op.drop_table("playback_rounds")
