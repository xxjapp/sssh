#!/usr/bin/env ruby
# encoding: utf-8
#

require "open3"

################################################################
# module

# See: https://nickcharlton.net/posts/ruby-subprocesses-with-stdout-stderr-streams.html
module OS
    # block => |o, e|
    # return all output and error if no block given otherwise empty string
    def self.popen3(cmd, listener: nil, user_data: nil, &block)
        output      = ''
        error       = ''
        io_threads  = []

        # see: http://stackoverflow.com/a/1162850/83386
        Open3.popen3(cmd) { |stdin, stdout, stderr, wait_thr|
            listener.send(:on_start, wait_thr, user_data) if listener && listener.respond_to?(:on_start)

            # stdin not supported
            stdin.close

            # read each stream from a new thread
            { out: stdout, err: stderr }.each { |key, stream|
                io_threads << Thread.new {
                    listener.send(:on_start_read, key) if listener && listener.respond_to?(:on_start_read)

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

            listener.send(:on_end, wait_thr, user_data) if listener && listener.respond_to?(:on_end)
        }

        return [output, error]
    end
end

################################################################
# test & usage

if __FILE__ == $0
    OS.popen3("(echo message) && (echo some error 1>&2)") { |o, e|
        $stdout.puts    o.chomp if o
        $stderr.puts    e.chomp if e
    }

    class Listener
        def on_start wait_thr, user_data
            puts
            puts "pid = #{wait_thr.pid}"
        end
    end

    OS.popen3("ping baidu.com", listener: Listener.new) { |o, e|
        $stdout.puts    o.chomp if o
        $stderr.puts    e.chomp if e
    }
end
