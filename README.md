# North American Sprint Scoring

This is software to help score the [North American Sprint](http://ssbsprint.com/) ham radio competition. The process
begins with a collection of [Cabrillo](http://www.kkn.net/~trey/cabrillo/) log files that contain records of ham
radio contacts that took place during the running of the NA Sprint contest.

The purpose of this software is to verify the information in the Cabrillo log files and apply the scoring rules to
calculate a score for each entry.  Verification can take many forms such as is the date & time in the period of
the contest, and it can include cross checking logs against each other.

The main difficulty of scoring ham radio contests is bad data. People will submit logs that do not match the
specification, and they will also incorrect incorrect data in the various fields.

The overall approach of this software is to put all the relevent log and contact data into a SQL database. The
verification and cross checking is processed using SQL queries and additional matches in the program.

# Steps from logs to reports

1. Review logs for matching system and other issues `ruby testcab.rb --checkonly *.log`. Use a powerful editor
   like [GNU Emacs](https://www.gnu.org/s/emacs) to edit the logs. The rectangle-orient commands in GNU Emacs are
   particularly useful.
2. Send the list of "missing logs": `ruby testcab.rb --checkonly --missing *.log` to the contest chairman. The
   chairman may choose to send email to try to get more logs. If successful, return to the previous step and check
   the new logs.
3. Read the logs into the MySQL database: `ruby testcab.rb --checkonly --new --name "Fall SSB Sprint" --year 2016
   --populate *.log`
4. 