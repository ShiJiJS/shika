"""Journal bounded image purges and known empty-directory cleanup."""

import sqlalchemy as sa
from alembic import op

revision = "0011"
down_revision = "0010"


def upgrade():
    op.add_column(
        "pack_trash_items",
        sa.Column("purged_pages", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_table(
        "pack_purge_executions",
        sa.Column("id", sa.String(), sa.ForeignKey("pack_file_operations.id"), primary_key=True),
        sa.Column(
            "plan_id",
            sa.String(),
            sa.ForeignKey("pack_purge_plans.id"),
            nullable=False,
            unique=True,
        ),
    )
    op.create_table(
        "pack_purge_steps",
        sa.Column("id", sa.String(), primary_key=True),
        sa.Column("parent_id", sa.String(), sa.ForeignKey("pack_file_steps.id"), nullable=False),
        sa.Column("kind", sa.String(), nullable=False),
        sa.Column("page_id", sa.String(), nullable=True),
        sa.Column("relative_path", sa.Text(), nullable=False),
        sa.Column("source_signature", sa.JSON(), nullable=False),
        sa.Column("expected_hash", sa.String(), nullable=True),
        sa.Column("expected_size", sa.Integer(), nullable=False),
        sa.Column("state", sa.JSON(), nullable=False),
        sa.Column("phase", sa.String(), nullable=False),
        sa.Column("outcome", sa.String(), nullable=False),
        sa.Column("error", sa.String(), nullable=True),
        sa.UniqueConstraint("parent_id", "kind", "relative_path"),
        sa.CheckConstraint("kind IN ('image','directory')"),
    )
    op.create_index("ix_pack_purge_steps_parent_id", "pack_purge_steps", ["parent_id"])


def downgrade():
    op.drop_table("pack_purge_steps")
    op.drop_table("pack_purge_executions")
    op.drop_column("pack_trash_items", "purged_pages")
