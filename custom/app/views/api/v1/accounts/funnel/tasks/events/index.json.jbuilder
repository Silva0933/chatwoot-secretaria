json.payload do
  json.array! @events do |event|
    json.id event.id
    json.event_type event.event_type
    json.source event.source
    json.data_before event.data_before
    json.data_after event.data_after
    json.created_at event.created_at
    if event.actor.present?
      json.actor do
        json.id event.actor.id
        json.type event.actor_type
        json.name event.actor.try(:name)
      end
    else
      json.actor nil
    end
  end
end
