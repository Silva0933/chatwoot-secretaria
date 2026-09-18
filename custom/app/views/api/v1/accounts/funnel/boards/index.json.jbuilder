json.payload do
  json.array! @boards do |board|
    json.partial! 'api/v1/accounts/funnel/boards/board', board: board
  end
end
