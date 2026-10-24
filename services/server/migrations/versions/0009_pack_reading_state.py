"""Version pack reader writes and explain scanner-adjusted resume positions."""

import sqlalchemy as sa
from alembic import op

revision = "0009"
down_revision = "0008"


def upgrade():
    op.add_column(
        "pack_progress",
        sa.Column("content_version", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column("pack_progress", sa.Column("recovery_reason", sa.String(), nullable=True))
    op.add_column(
        "pack_preferences", sa.Column("revision", sa.Integer(), nullable=False, server_default="0")
    )
    op.execute(
        "UPDATE pack_progress SET content_version = (SELECT content_version FROM packs WHERE packs.id = pack_progress.pack_id)"
    )


def downgrade():
    op.drop_column("pack_preferences", "revision")
    op.drop_column("pack_progress", "recovery_reason")
    op.drop_column("pack_progress", "content_version")
