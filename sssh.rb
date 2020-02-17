#!/usr/bin/env ruby
# encoding: utf-8
#
# env example:
# SSSH_LOG_DIR = "/var/log/ruby"
# SSSH_SSH_CMD = "ssh -vNT -R 23389:localhost:3389 user@example.com -p 22"
#

require "open3"

require_relative "loggingx"
require_relative "os"

SSSH_LOG_DIR = ENV["SSSH_LOG_DIR"]
SSSH_SSH_CMD = ENV["SSSH_SSH_CMD"]

$log ||= LoggingX.get_log File.basename(__FILE__), log_dir: SSSH_LOG_DIR, log_level: :debug

################################################################
# module

module Sssh
    def self.start
        cmd = SSSH_SSH_CMD

        loop {
            OS.popen3(cmd) { |o, e|
                $log.info o.chomp if o
                $log.error e.chomp if e
            }
        }
    end
end

################################################################
# main

if __FILE__ == $0
    Sssh.start
end
