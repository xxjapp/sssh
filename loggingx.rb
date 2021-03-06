#!/usr/bin/env ruby
# encoding: utf-8
#
# LoggingX v1.0
#

require "logging"

################################################################
# LoggingX

module LoggingX
    DEFAULT_LOG_DIR     = "/var/log/ruby"
    DEFAULT_LOG_LEVEL   = :debug
    DEFAULT_PATTERN     = "%d %-5l [%t] (%F:%L) %M - %m\n"

    DATE_PATTERN        = "%Y-%m-%d %H:%M:%S.%L"

    # here we setup a color scheme called "bright"
    Logging.color_scheme("bright",
        levels: {
            info: :green,
            warn: :yellow,
            error: :red,
            fatal: [:white, :on_red]
        },
        date: :blue,
        logger: :cyan,
        message: :magenta
    )

    def self.get_log name, options = {}
        options[:log_dir]   ||= DEFAULT_LOG_DIR
        options[:log_level] ||= DEFAULT_LOG_LEVEL
        options[:pattern]   ||= DEFAULT_PATTERN

        FileUtils.mkdir_p options[:log_dir]

        log = Logging.logger[name]
        log.add_appenders(
            Logging.appenders.stdout(
                "stdout", layout: Logging.layouts.pattern(
                    pattern: options[:pattern],
                    date_pattern: DATE_PATTERN,
                    color_scheme: "bright"
                )
            ),
            Logging.appenders.rolling_file(
                "#{options[:log_dir]}/#{name}.log", layout: Logging.layouts.pattern(
                    pattern: options[:pattern],
                    date_pattern: DATE_PATTERN
                ), age: "daily"
            )
        )

        log.level = options[:log_level]
        log.caller_tracing = true

        log
    end

    def self.get_current_thread_id name = nil
        if name
            name + "-" + Thread.current.object_id.to_s(32)
        else
            Thread.current.object_id.to_s(32)
        end
    end
end

################################################################
# test & usage

if __FILE__ == $0
    log ||= LoggingX.get_log File.basename(__FILE__), log_dir: "/var/log/ruby", log_level: :debug, pattern: "%d %-5l [%X{tid}] (%F:%L) %M - %m\n"

    Logging.mdc['tid'] = LoggingX.get_current_thread_id "thread-name"

    # These messages will be logged to both the log file and to STDOUT
    log.debug "a very nice little debug message"
    log.warn "this is your last warning"
end
