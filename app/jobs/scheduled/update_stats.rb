# frozen_string_literal: true

module Jobs
  class UpdateStats < ::Jobs::Scheduled
    every 1.hour

    def execute(args = {})
      postgres_highest_sequence = DB.query_single(<<~SQL)[0]
          WITH columns AS MATERIALIZED (
            SELECT table_name,
                  column_name,
                  data_type column_type,
                  REPLACE(REPLACE(column_default, 'nextval(''', ''), '''::regclass)', '') sequence_name
            FROM information_schema.columns
            WHERE table_schema = 'public' AND column_default LIKE '%nextval(''%'
          ), sequences AS MATERIALIZED (
            SELECT sequencename sequence_name,
                  data_type::text sequence_type,
                  COALESCE(last_value, 0) last_value
            FROM pg_sequences
          )
          SELECT MAX(last_value)
          FROM columns
          JOIN sequences ON sequences.sequence_name = columns.sequence_name
          WHERE columns.column_type = 'integer' OR
                -- The column and sequence types should match, but this is just an extra check.
                sequences.sequence_type = 'integer' OR
                -- The `id` column of these tables is a `bigint`, but the foreign key columns are usually integers.
                -- These columns will be migrated in the future.
                -- See https://github.com/discourse/discourse/blob/6e1aeb1f504f469ceed189c24d43a7a99b8970c7/spec/rails_helper.rb#L480-L490
                table_name IN ('reviewables', 'flags', 'sidebar_sections')
        SQL

      Discourse.stats.set("postgres_highest_sequence", postgres_highest_sequence)
    end
  end
end
