"""Persist confirmed missing-pack cleanup scope and per-member results."""

import sqlalchemy as sa
from alembic import op

revision = "0013"
down_revision = "0012"


def upgrade():
    op.create_table(
        "pack_missing_cleanups",
        sa.Column("id", sa.String(), sa.ForeignKey("tasks.id"), primary_key=True),
        sa.Column("request_id", sa.String(), nullable=False, unique=True),
        sa.Column("historical", sa.Boolean(), nullable=False),
    )
    op.create_table(
        "pack_missing_members",
        sa.Column(
            "cleanup_id", sa.String(), sa.ForeignKey("pack_missing_cleanups.id"), primary_key=True
        ),
        sa.Column("pack_id", sa.String(), sa.ForeignKey("packs.id"), primary_key=True),
        sa.Column("root_id", sa.String(), sa.ForeignKey("roots.id"), nullable=False),
        sa.Column("generation", sa.Integer(), nullable=False),
        sa.Column("name", sa.String(), nullable=False),
        sa.Column("path", sa.Text(), nullable=False),
        sa.Column("outcome", sa.String(), nullable=False),
        sa.Column("error", sa.String(), nullable=True),
    )
    op.create_index(
        "ix_pack_missing_pending", "pack_missing_members", ["cleanup_id", "outcome", "pack_id"]
    )


def downgrade():
    op.drop_table("pack_missing_members")
    op.drop_table("pack_missing_cleanups")
