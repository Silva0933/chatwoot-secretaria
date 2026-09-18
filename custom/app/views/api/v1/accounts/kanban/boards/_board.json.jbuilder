json.id board.id
json.name board.name
json.description board.description
json.created_at board.created_at
json.steps board.steps.map do |step|
  json.id step.id
  json.name step.name
  json.color step.color
  json.cancelled step.stage_lost?
end
json.inbox_ids board.board_inboxes.map(&:inbox_id)
json.agent_ids board.members.map(&:user_id)
