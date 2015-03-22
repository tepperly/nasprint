#!/usr/local/bin/ruby
# -*- encoding: utf-8 -*-
# NA Sprint SSB Download Logs from Email
# Tom Epperly NS6T
# ns6t@arrl.net
#
#

require 'mail'
require 'tempfile'
require 'getoptlong'
require 'net/imap'
require 'tempfile'


$userID = nil
$password = nil
$server="www15.website-server.net"

def htmlToPlain(str)
  file = Tempfile.new('cqp_html_txt', :encoding => Encoding::UTF_8)
  file.write(str)
  file.close
  IO.popen("w3m -dump -T \"text/html\" -I UTF-8 -O UTF-8 #{file.path}", :encoding => Encoding::UTF_8) { |input|
    str = input.read
  }
  return str
end

def extractLogInfo(str, date)
  extratext = ""
  if str =~ /^Your Name\s*([^\n\r]+)\s*Your Callsign/m
    name = $1.strip.gsub(/\s{2,}/, " ")
    extratext << "X-SSBSPRINT-NAME: #{name}\n"
  else
    name = nil
  end
  if str =~ /Your Callsign\s*([^\n\r]+)\s*Callsign Used/m
    callsign = $1.strip.upcase
    extratext << "X-SSBSPRINT-OPCALL: #{callsign}\n"
  else
    callsign = nil
  end
  if str =~ /Callsign Used In Contest\s*([^\n\r]+)\s*Email/m
    contestcall = $1.strip.upcase
    extratext << "X-SSBSPRINT-CALL: #{contestcall}\n"
  else
    contestcall = nil
  end
  if str =~ /Email\s*([^\n]+)\s*Or Paste/m
    email = $1
    extratext << "X-SSBSPRINT-EMAIL: #{email}\n"
  else
    email = nil
  end
  if date
    extratext << "X-SSBSPRINT-SUBMIT: #{date.to_s}\n"
  end
  if str =~ /Or Paste Cabrillo Log Text Here\s*(.*)/m
    log = $1.strip
    log = log.gsub(/^\s+/, "") # remove leading space on every line
    ind = log.index(/^QSO:/)
    if ind
      log = log.insert(ind, extratext)
    end
  else
    log = nil
  end
  return log, contestcall
end


opts = GetoptLong.new(
                      [ '--user', '-u', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--password', '-p', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--server', '-s', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT]
                      )

opts.each { |opt,arg|
  case opt
  when '--user'
    $userID = arg.strip
  when '--password'
    $password = arg.strip
  when '--server'
    $server  = arg
  when '--help'
    print "downloadlogs.rb --user <userid> --password <password> [--server <imapserver>"
  end
}

def extractLogFromMail(mailMsg)
  if not mailMsg.multipart?
    plainTxt = htmlToPlain(mailMsg.body.decoded)
    log, contestcall = extractLogInfo(plainTxt, mailMsg.date)
    if log
      open(contestcall.to_s + "_" + mailMsg.date.strftime("%Y-%m-%d_%H%M%S.log"),
           "w:ascii") { |out|
        out.write(log)
      }
    end
  end
end

if $userID and $password
  imap = Net::IMAP.new($server.to_s, 993, true)
  print "Connected\n"
  print "Trying to login user: '#{$userID}' password '#{$password}'\n"
  imap.authenticate("LOGIN",$userID, $password)
  print "Authenticated\n"
  imap.examine("INBOX")
  print "Switched folder\n"
  msgs = imap.uid_search(["SUBJECT", "Log Submission for"])
  print "Done searching\n"

  msgs.each { |msgUID|
    print "Fetching #{msgUID}\n"
    emailMessage = imap.uid_fetch(msgUID, "RFC822")
    msgText = emailMessage[0].attr["RFC822"]
    mailMsg = Mail.new(msgText)
    extractLogFromMail(mailMsg)
  }

  imap.logout
  imap.disconnect
else
  print "Requires user ID and password."
end
