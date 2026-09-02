json.id board.id
json.name board.name
json.description board.description
json.archived_at board.archived_at
json.created_at board.created_at
json.steps board.steps.map do |step|
  json.id step.id
  json.name step.name
  json.description step.description
  json.color step.color
  json.rank step.rank.to_s
  json.stage_type step.stage_type
end
