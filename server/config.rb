#!/usr/local/bin/ruby
# -*- encoding: utf-8 -*-
# CQP configuration information
# Tom Epperly NS6T
# ns6t@arrl.net
#
#
require 'date'

module CQPConfig
  CONTEST_DEADLINE=DateTime.new(2021,10,18,23,59,59, "-12:00").to_time
  CONTEST_YEAR=(DateTime.now-90).year
  
  DATABASE_HOST="localhost"
  DATABASE_USER="cqpXXXX"
  DATABASE_PASSWORD="XXXXXXXX"

  READ_ONLY_USER="cqpbackupXXXX"
  READ_ONLY_PASSWORD="xxxxx"

  EMAIL_SERVER="smtp.gmail.com"
  EMAIL_PORT=587
  EMAIL_NAME="Northern California Contest Club"
  EMAIL_USER="username"
  EMAIL_PASSWORD="password"
  EMAIL_ADDRESS=EMAIL_USER+"@gmail.com"
  EMAIL_LOGIN_REQUIRED=true
  EMAIL_USE_TLS=true

  EMAIL_OAUTH2_CLIENT_ID="secret_from_google_com"
  EMAIL_OAUTH2_CLIENT_SECRET="another_secret"
  EMAIL_OAUTH2_REFRESH_TOKEN="user-level-secret"

  INCOMING_IMAP_HOST="imap.gmail.com"
  INCOMING_IMAP_PORT=993
  INCOMING_IMAP_USER="username@gmail.com"
  
  INCOMING_IMAP_FOLDER="Inbox"
  INCOMING_IMAP_SUCCESS_FOLDER="CQP#{CONTEST_YEAR}/Log"
  INCOMING_IMAP_FAIL_FOLDER="CQP#{CONTEST_YEAR}/Unknown"
  INCOMING_IMAP_ARCHIVE="CQP#{CONTEST_YEAR}"
end
