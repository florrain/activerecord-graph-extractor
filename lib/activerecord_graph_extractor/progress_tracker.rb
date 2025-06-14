# frozen_string_literal: true

require 'json'

module ActiveRecordGraphExtractor
  class ProgressTracker
    attr_reader :enabled, :total_records, :processed_records, :model_progress, :start_time

    def initialize(enabled: true, output: $stdout, total_records: 0)
      @enabled = enabled
      @output = output
      @start_time = nil
      @total_records = total_records
      @processed_records = 0
      @model_progress = {}
    end

    def start
      @start_time = Time.now
    end

    def start_extraction(total_count)
      return unless @enabled

      @total_records = total_count
      @start_time = Time.now
      log_info("🚀 Starting extraction of #{format_number(total_count)} records...")
    end

    def update_progress(current_count, message = nil)
      return unless @enabled

      percentage = @total_records > 0 ? (current_count * 100.0 / @total_records).round(1) : 0

      status = "📊 Progress: #{format_number(current_count)}/#{format_number(@total_records)} (#{percentage}%)"
      status += " - #{message}" if message

      log_info(status)
    end

    def complete_extraction(final_count, duration)
      return unless @enabled

      rate = duration > 0 ? (final_count / duration).round(1) : 0
      log_info("✅ Extraction completed! #{format_number(final_count)} records in #{format_duration(duration)} (#{rate} records/sec)")
    end

    def start_import(total_count)
      return unless @enabled

      @total_records = total_count
      @start_time = Time.now
      log_info("🚀 Starting import of #{format_number(total_count)} records...")
    end

    def complete_import(final_count, duration)
      return unless @enabled

      rate = duration > 0 ? (final_count / duration).round(1) : 0
      log_info("✅ Import completed! #{format_number(final_count)} records in #{format_duration(duration)} (#{rate} records/sec)")
    end

    def log_model_progress(model_name, current, total = nil)
      if total.nil?
        # If only current is provided, assume it's a simple increment
        @model_progress[model_name] ||= { current: 0, total: 1, percentage: 0 }
        @model_progress[model_name][:current] = current
        @model_progress[model_name][:percentage] = 100
      else
        percentage = total > 0 ? (current * 100.0 / total).round(1) : 0
        @model_progress[model_name] = {
          current: current,
          total: total,
          percentage: percentage
        }
        
        if @enabled
          log_info("📝 #{model_name}: #{format_number(current)}/#{format_number(total)} (#{percentage}%)")
        end
      end
    end

    def increment
      @processed_records += 1
    end

    def progress_percentage
      return 0 if @total_records == 0
      (@processed_records * 100.0 / @total_records).round(1)
    end

    def elapsed_time
      return 0 unless @start_time
      Time.now - @start_time
    end

    def estimated_time_remaining
      return 0 if @processed_records == 0 || @total_records == 0 || @processed_records >= @total_records
      
      elapsed = elapsed_time
      rate = @processed_records / elapsed
      remaining_records = @total_records - @processed_records
      remaining_records / rate
    end

    def records_per_second
      return 0 if @processed_records == 0 || elapsed_time == 0
      @processed_records / elapsed_time
    end

    def complete?
      @total_records > 0 && @processed_records >= @total_records
    end

    def reset
      @processed_records = 0
      @model_progress = {}
      @start_time = nil
    end

    def to_s
      "Progress: #{@processed_records}/#{@total_records} (#{progress_percentage}%)"
    end

    def to_json(*args)
      {
        total_records: @total_records,
        processed_records: @processed_records,
        progress_percentage: progress_percentage,
        elapsed_time: elapsed_time,
        estimated_time_remaining: estimated_time_remaining,
        records_per_second: records_per_second,
        model_progress: @model_progress,
        complete: complete?
      }.to_json(*args)
    end

    def log_progress_to_io(io)
      io.puts(to_s)
      io.puts("Elapsed: #{format_duration(elapsed_time)}")
      io.puts("Remaining: #{format_duration(estimated_time_remaining)}")
      
      @model_progress.each do |model, progress|
        io.puts("#{model}: #{progress[:current]}/#{progress[:total]} (#{progress[:percentage]}%)")
      end
    end

    def log_error(message)
      # Always show errors, even if progress is disabled
      @output.puts("❌ ERROR: #{message}")
    rescue StandardError
      # Silently ignore output errors
    end

    def log_warning(message)
      return unless @enabled

      @output.puts("⚠️  WARNING: #{message}")
    rescue StandardError
      # Silently ignore output errors
    end

    def log_info(message)
      return unless @enabled

      @output.puts(message)
    rescue StandardError
      # Silently ignore output errors
    end

    def log_memory_usage
      return unless @enabled

      memory_mb = current_memory_usage
      log_info("💾 Memory usage: #{memory_mb} MB")
    end

    def current_memory_usage
      if defined?(GC.stat)
        (GC.stat[:heap_allocated_pages] * 4096 / 1024.0 / 1024.0).round(1)
      else
        0.0
      end
    end

    private

    def format_number(number)
      number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    def format_duration(seconds)
      if seconds < 60
        "#{seconds.round(2)}s"
      else
        minutes = (seconds / 60).floor
        remaining_seconds = (seconds % 60).round
        "#{minutes}m #{remaining_seconds}s"
      end
    end
  end
end
