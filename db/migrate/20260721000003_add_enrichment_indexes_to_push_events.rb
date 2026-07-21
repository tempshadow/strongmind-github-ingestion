class AddEnrichmentIndexesToPushEvents < ActiveRecord::Migration[7.1]
  def change
    # No foreign keys: enrichment may be skipped for budget, so a push event can
    # legitimately reference an actor or repository row that does not exist yet.
    add_index :push_events, [:repo_id, :event_created_at]
  end
end
