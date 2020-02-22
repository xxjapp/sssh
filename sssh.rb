#!/usr/bin/env ruby
# encoding: utf-8
#
# Usage:
#   ruby sssh.rb --help
#
# Example:
#   ruby sssh.rb --host locahost --port 22 --remote_port 20022 --local_port 22
#

require_relative "loggingx"
require_relative "os"

################################################################
# class Sssh

class Sssh
    def initialize params
        @user               = params["user"]
        @host               = params["host"]
        @port               = params["port"]
        @remote_port        = params["remote_port"]
        @local_port         = params["local_port"]
        @ssh_path           = params["ssh_path"]
        @remote_log_path    = params["remote_log_path"]

        @cmd    = "ssh -NT -R #{@remote_port}:localhost:#{@local_port} #{user_at_host} -p #{@port}"         # cmd to create reverse ssh tunneling
        @cmd2   = "ssh #{user_at_host} -p #{@port} \"netstat -ano | grep :#{@remote_port} | wc -l\""        # cmd to check the created reverse ssh tunneling
        @cmd3   = "rsync -avzhe '#{@ssh_path} -p #{@port}' #{@log_dir} #{user_at_host}:#{@remote_log_path}" # cmd to rsync log to remote host

        @log_dir = params["log_dir"]
        $log ||= LoggingX.get_log File.basename(__FILE__), log_dir: @log_dir, log_level: :debug, pattern: "%d %-5l [%X{tid}] (%F:%L) %M - %m\n"
    end

    def user_at_host
        @user ? "#{@user}@#{@host}" : @host
    end

    def start
        start_monitor
        start_rsync_log_file

        loop {
            OS.popen3(@cmd, listener: self) { |o, e|
                $log.info  o.chomp if o
                $log.error e.chomp if e
            }

            wait_interval Time.now - @process_info[:start_time]
        }
    end

    def wait_interval execute_time
        interval = [1, 60 - execute_time].max
        $log.debug "sleep #{interval}"
        sleep interval
    end

    def on_start wait_thr
        # started process info
        @process_info = {
            cmd:            @cmd,
            pid:            wait_thr.pid,		# pid of the started process.
            start_time:     Time.now,
            status:         :start
        }

        $log.debug "@process_info = #{@process_info}"
    end

    def on_end wait_thr
        @process_info.merge!({
            exit_status:    wait_thr.value,	    # Process::Status object returned.
            end_time:       Time.now,
            status:         :end
        })

        $log.debug "@process_info = #{@process_info}"
    end

    def on_start_read key
        Logging.mdc['tid'] = LoggingX.get_current_thread_id key.to_s
    end

    def start_monitor
        Thread.new {
            Logging.mdc['tid'] = LoggingX.get_current_thread_id "monitor"

            loop {
                sleep 60

                process_info = @process_info
                kill_current_connection process_info if !status_ok? process_info
            }
        }
    end

    def kill_current_connection process_info
        if process_info[:status] == :end
            $log.debug "Already end"
            return
        end

        $log.info "kill #{process_info[:pid]}"

        begin
            Process.kill("KILL", process_info[:pid])
        rescue => exception
            $log.error exception
        end
    end

    def status_ok? process_info
        if process_info[:status] == :end
            $log.debug "Already end"
            return true
        end

        if Time.now - process_info[:start_time] < 60
            $log.debug "Started less then one minute, wait and see..."
            return true
        end

        $log.debug "@cmd2 = #{@cmd2}"
        res = `#{@cmd2}`.chomp

        if res.to_i >= 2
            $log.info  "#{res} (OK)"
        else
            $log.error "#{res} (NG)"
        end

        res.to_i >= 2
    end

    def start_rsync_log_file
        Thread.new {
            Logging.mdc['tid'] = LoggingX.get_current_thread_id "rsync_log"

            loop {
                sleep 60

                # NOTE: touch log_dir to force cloud storage service like Dropbox to upload log files
                FileUtils.touch Dir.glob "#{@log_dir}/*.log"

                OS.popen3(@cmd3) { |o, e|
                    $log.info  o.chomp if o
                    $log.error e.chomp if e
                }
            }
        }
    end
end

################################################################
# main

if __FILE__ == $0
    require 'optparse'
    params = ARGV.getopts nil, "user:", "host:localhost", "port:22", "remote_port:20022", "local_port:22", "ssh_path:C:/cygwin64/bin/ssh.exe", "remote_log_path:/tmp/log/", "log_dir:/var/log/ruby"

    Logging.mdc['tid'] = LoggingX.get_current_thread_id "main"
    Sssh.new(params).start
end
