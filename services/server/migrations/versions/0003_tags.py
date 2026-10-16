"""Stable flat tags, many-to-many associations and idempotent metadata writes."""

import sqlalchemy as sa
from alembic import op

revision = "0003"
down_revision = "0002"


def upgrade():
    op.create_table(
        "tags",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("name", sa.String(), nullable=False, unique=True),
        sa.Column("created_at", sa.Float(), nullable=False),
    )
    op.create_table(
        "video_tags",
        sa.Column(
            "video_id",
            sa.String(),
            sa.ForeignKey("videos.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "tag_id", sa.String(), sa.ForeignKey("tags.id", ondelete="CASCADE"), primary_key=True
        ),
    )
    op.create_index("video_tags_tag_video", "video_tags", ["tag_id", "video_id"])
    op.create_table(
        "request_records",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("fingerprint", sa.String(), nullable=False),
        sa.Column("result", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.Float(), nullable=False),
    )


def downgrade():
    op.drop_table("request_records")
    op.drop_table("video_tags")
    op.drop_table("tags")
