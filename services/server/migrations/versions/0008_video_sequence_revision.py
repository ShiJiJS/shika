"""Separate queue changes from ordinary position receipts for bounded clients."""

import sqlalchemy as sa
from alembic import op

revision = "0008"
down_revision = "0007"


def upgrade():
    op.add_column(
        "playback_rounds",
        sa.Column("sequence_revision", sa.Integer(), nullable=False, server_default="0"),
    )


def downgrade():
    op.drop_column("playback_rounds", "sequence_revision")
