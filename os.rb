#!/usr/bin/env ruby
# encoding: utf-8
#

require "open3"

require_relative "loggingx"

$log ||= LoggingX.get_log File.basename(__FILE__), log_dir: "/var/log/ruby", log_level: :debug

################################################################
# module

# See: https://nickcharlton.net/posts/ruby-subprocesses-with-stdout-stderr-streams.html
module OS
    # block => |o, e|
    # return all output and error if no block given otherwise empty string
    def self.popen3(cmd, &block)
        output      = ''
        error       = ''
        io_threads  = []

        # see: http://stackoverflow.com/a/1162850/83386
        Open3.popen3(cmd) { |stdin, stdout, stderr, wait_thr|
            pid = wait_thr.pid                  # pid of the started process.

            $log.info "cmd = #{cmd}"
            $log.info "pid = #{pid}"

            # stdin not supported
            stdin.close

            # read each stream from a new thread
            { out: stdout, err: stderr }.each { |key, stream|
                io_threads << Thread.new {
                    until (line = stream.gets).nil? do
                        if block_given?
                            # yield the block depending on the stream
                            if key == :out
                                yield line, nil
                            else
                                yield nil, line
                            end
                        else
                            if key == :out
                                output += line
                            else
                                error  += line
                            end
                        end
                    end
                }
            }

            # wait for all io threads' ending
            io_threads.each { |t| t.join }

            exit_status = wait_thr.value        # Process::Status object returned.

            $log.info ""
            $log.info "exit_status = #{exit_status}"
        }

        return [output, error]
    end
end

################################################################
# test & usage

if __FILE__ == $0
    OS.popen3("(echo message) && (echo some error 1>&2)") { |o, e|
        $log.info   o.chomp if o
        $log.error  e.chomp if e
    }

    OS.popen3("ping baidu.com") { |o, e|
        $log.info   o.chomp if o
        $log.error  e.chomp if e
    }
end
