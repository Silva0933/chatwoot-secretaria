json.payload do
  json.array! @steps do |step|
    json.id step.id
    json.name step.name
    json.description step.description
    json.color step.color
    # "cancelled" no contrato da Pro e o balde de perdido. O nosso stage_type diz o mesmo.
    json.cancelled step.stage_lost?
    json.won step.stage_won?
  end
end
