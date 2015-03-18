#
require_relative "database"
require_relative "ContestDB"
db = makeDB
o = ContestDatabase.new(db)
