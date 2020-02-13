#!/usr/bin/env ruby
# encoding: utf-8
#

require "colorize"
require "open3"

require_relative "loggingx"

$log ||= LoggingX.get_log File.basename(__FILE__), log_dir: "/var/log/ruby", log_level: :debug

################################################################
# module

module Sssh
    def self.start
        cmd = "ssh -R 20022:localhost:22 localhost -p 22"
        $log.info cmd.green

        loop {
            Open3.popen3(cmd) { |stdin, stdout, stderr, wait_thr|
                pid = wait_thr.pid                  # pid of the started process.
                $log.info "pid = #{pid}"

                # ...

                exit_status = wait_thr.value        # Process::Status object returned.
                $log.info "exit_status = #{exit_status}"
            }
        }
    end
end

################################################################
# main

if __FILE__ == $0
    Sssh.start
end
