#!/usr/bin/env ruby
# encoding: utf-8
#
# Usage:
#   ruby sssh.rb --help
#
# Example:
#   ruby sssh.rb --host localhost --port 22 --tunnels "{20022: 22, 23389: 3389}"
#
# Note:
#   --tunnels use simplified json format
#

require "date"
require "json"

require_relative "loggingx"
require_relative "os"

################################################################
# class Sssh

class Sssh
    def initialize params
        # params to ssh remote host
        @user                   = params["user"]
        @host                   = params["host"]
        @port                   = params["port"]

        # params to create tunnels
        @tunnels                = JSON.parse params["tunnels"].gsub /(\w+)/, '"\1"'

        # params to rsync log files to remote host
        @ssh_path               = params["ssh_path"]
        @log_dir                = params["log_dir"]
        @remote_log_parent_dir  = params["remote_log_parent_dir"]

        # hash of remote_port to process info
        @process_info           = {}

        @log                    = LoggingX.get_log File.basename(__FILE__), log_dir: @log_dir, log_level: :debug, pattern: "%d %-5l [%X{tid}] (%F:%L) %M - %m\n"
    end

    def user_at_host
        @user ? "#{@user}@#{@host}" : @host
    end

    def cygdrive_path path
        "/cygdrive/" + path.sub(/^(\w):/, "\\1")
    end

    # cmd to create ssh tunnels
    def tunnel_cmd remote_port, local_port
        "ssh -NT -R #{remote_port}:localhost:#{local_port} #{user_at_host} -p #{@port}"
    end

    # cmd to check the created ssh tunnels
    def check_cmd remote_port
        "ssh #{user_at_host} -p #{@port} \"netstat -ano | grep :#{remote_port} | wc -l\""
    end

    # cmd to rsync log to remote host
    def sync_cmd
        "rsync --delete -avzhe '#{@ssh_path} -p #{@port}' #{cygdrive_path @log_dir} #{user_at_host}:#{@remote_log_parent_dir}"
    end

    def start
        threads = [start_rsync_log_file]

        @tunnels.each { |remote_port, local_port|
            threads << start_tunnel(remote_port, local_port)
            threads << start_monitor(remote_port)
        }

        threads.each { |t| t.join }
    end

    def start_tunnel remote_port, local_port
        Thread.new {
            Logging.mdc['tid'] = LoggingX.get_current_thread_id "tunnel"

            loop {
                OS.popen3(tunnel_cmd(remote_port, local_port), listener: self, user_data: remote_port) { |o, e|
                    @log.info  o.chomp if o
                    @log.error e.chomp if e
                }

                wait_interval Time.now - @process_info[remote_port][:start_time]
            }
        }
    end

    def wait_interval execute_time
        interval = [1, 60 - execute_time].max
        @log.debug "sleep #{interval}"
        sleep interval
    end

    def on_start wait_thr, remote_port
        # started process info
        @process_info[remote_port] = {
            remote_port:    remote_port,
            pid:            wait_thr.pid,		# pid of the started process.
            start_time:     Time.now,
            status:         :start
        }

        @log.debug "@process_info[#{remote_port}] = #{@process_info[remote_port]}"
    end

    def on_end wait_thr, remote_port
        @process_info[remote_port].merge!({
            exit_status:    wait_thr.value,	    # Process::Status object returned.
            end_time:       Time.now,
            status:         :end
        })

        @log.debug "@process_info[#{remote_port}] = #{@process_info[remote_port]}"
    end

    def on_start_read key
        Logging.mdc['tid'] = LoggingX.get_current_thread_id key.to_s
    end

    def start_monitor remote_port
        Thread.new {
            Logging.mdc['tid'] = LoggingX.get_current_thread_id "monitor"

            loop {
                sleep 60

                pinfo = @process_info[remote_port]
                kill_current_connection pinfo if !status_ok? pinfo
            }
        }
    end

    def kill_current_connection pinfo
        if pinfo[:status] == :end
            @log.debug "Already end"
            return
        end

        @log.info "kill #{pinfo[:pid]}"

        begin
            Process.kill("KILL", pinfo[:pid])
        rescue => exception
            @log.error exception
        end
    end

    def status_ok? pinfo
        if pinfo[:status] == :end
            @log.debug "Already end"
            return true
        end

        if Time.now - pinfo[:start_time] < 60
            @log.debug "Started less then one minute, wait and see..."
            return true
        end

        res = `#{check_cmd pinfo[:remote_port]}`.chomp

        if res.to_i >= 2
            @log.info  "#{res} (OK)"
        else
            @log.error "#{res} (NG)"
        end

        res.to_i >= 2
    end

    def start_rsync_log_file
        Thread.new {
            Logging.mdc['tid'] = LoggingX.get_current_thread_id "rsync_log"

            loop {
                sleep 60

                # delete old log files
                Dir.glob("#{@log_dir}/**/*").older_than_days(90) { |file|
                    FileUtils.rm(file) if File.file?(file)
                }

                OS.popen3(sync_cmd) { |o, e|
                    @log.info  o.chomp if o
                    @log.error e.chomp if e
                }
            }
        }
    end
end

################################################################
# module Enumerable

# SEE: https://stackoverflow.com/a/23250497/1440174
module Enumerable
    def older_than_days(days)
        now = Date.today

        each { |file|
            yield file if (now - File.stat(file).mtime.to_date) > days
        }
    end
end

################################################################
# main

if __FILE__ == $0
    require 'optparse'
    params = ARGV.getopts nil,
        "user:",
        "host:localhost",
        "port:22",
        "tunnels:{20022: 22, 23389: 3389}",
        "ssh_path:C:/cygwin64/bin/ssh.exe",
        "log_dir:C:/var/log/sssh",
        "remote_log_parent_dir:/tmp"

    Logging.mdc['tid'] = LoggingX.get_current_thread_id "main"
    Sssh.new(params).start
end
