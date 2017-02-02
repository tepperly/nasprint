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

# Getting the logs into shape and into a database

0. Edit cabrillo.rb and set CONTEST_START and CONTEST_END appropriately.
1. Review logs for matching system and other issues `ruby testcab.rb --checkonly *.log`. Use a powerful editor
   like [GNU Emacs](https://www.gnu.org/s/emacs) to edit the logs. The rectangle-orient commands in GNU Emacs are
   particularly useful.
2. Send the list of "missing logs": `ruby testcab.rb --checkonly --missing *.log` to the contest chairman. The
   chairman may choose to send email to try to get more logs. If successful, return to the previous step and check
   the new logs.
3. Read the logs into the MySQL database: `ruby testcab.rb --checkonly --new --name "Fall SSB Sprint" --year 2016
   --populate *.log`
4. If you need to start over (reload all the logs), it's `ruby testcab.rb --checkonly --new --name "Fall SSB Sprint"
   --year 2016 --restart --populate *.log`

# Cross matching the QSOs in the database

Now the logs and QSOs are in the database. You don't need to mess with the log files again unless you discover
issues that need to be fixed or more logs arrive.

1. Make some directories the program expects to already exist: `mkdir xml_db output`
2. Start the cross matching by running `ruby testcross.rb --name "Fall SSB Sprint" --year 2016 --qrzuser callsign
   --qrzpwd password` where callsign and password are a subscribers callsign and password.  To redo the cross
   matching, add `--restart`.
3. Review the name mismatches, `grep "name mismatch" output/*_cab.txt`. You may want to add new homophones to
   the homophones.csv file in the src directory. They will get added to the database the next time you run.  If
   you change the homophones.csv file, you will need to run again with `--restart`.
3. Set start and end in the Contest table of the MySQL database for this contest running. (Go into MySql)
4. Generate the report `ruby asciireport.rb --name "Fall SSB Sprint" --year 2016`
5. Load up scores_Fall_SSB_Sprint2016.csv and toxic_Fall_SSB_Sprint2016.csv in a spreadsheet program and
   review.  In particular, format the % Toxic column of the toxic report as a percentage, and then sort
   the whole toxic worksheet by % Toxic decreasing. This will cause the most toxic logs to appear at the
   top of the list. A toxic log is one that gives lots of partials, NILs or other bad QSOs to other stations.
   Any log with a toxic percent higher than 10% deserves review and maybe some less than 10% too.
6. For a toxic log, look at what the other logs got dinged for. For example, if the toxic log was
   NS6T I use, `awk '$1=="QSO:" && $10=="NS6T" { print}' output/*_cab.txt` to get a list of all the QSOs
   from the logs who worked NS6T. This assumes you have the Linux/Unix tool awk.  Any consistent error
   across multiple logs may indicate a mistake in the sent information of NS6T's log.  For example,
   NS6T's log might have a sent name of THOMAS, but if everything logged him as TOM giving the all
   partial matches, chances are that NS6T actually transmitted TOM instead of THOMAS. Use your judgement.
   You may end up editing NS6T's log and going back to loading the QSOs from the log file.
 

