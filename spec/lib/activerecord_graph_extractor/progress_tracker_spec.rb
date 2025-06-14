# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::ProgressTracker do
  let(:output) { StringIO.new }
  let(:tracker) { described_class.new(output: output) }
  let(:order) { create(:test_order) }
  let(:product) { create(:test_product) }
  let(:user) { create(:test_user) }

  describe '#initialize' do
    it 'creates a tracker with default settings' do
      default_tracker = described_class.new
      expect(default_tracker.enabled).to be(true)
    end

    it 'accepts custom output stream' do
      expect(tracker.instance_variable_get(:@output)).to eq(output)
    end

    it 'can be disabled' do
      disabled_tracker = described_class.new(enabled: false)
      expect(disabled_tracker.enabled).to be(false)
    end

    it 'initializes with default values' do
      expect(tracker.total_records).to eq(0)
      expect(tracker.processed_records).to eq(0)
      expect(tracker.model_progress).to eq({})
      expect(tracker.start_time).to be_nil
    end

    it 'accepts custom total records' do
      tracker = described_class.new(total_records: 100)
      expect(tracker.total_records).to eq(100)
    end
  end

  describe '#start_extraction' do
    it 'displays extraction start message' do
      tracker.start_extraction(100)
      
      expect(output.string).to include('Starting extraction')
      expect(output.string).to include('100')
    end

    it 'does nothing when disabled' do
      disabled_tracker = described_class.new(enabled: false, output: output)
      disabled_tracker.start_extraction(100)
      
      expect(output.string).to be_empty
    end
  end

  describe '#update_progress' do
    it 'updates progress with current count' do
      fresh_output = StringIO.new
      fresh_tracker = described_class.new(output: fresh_output)
      fresh_tracker.start_extraction(100)
      
      fresh_tracker.update_progress(25, 'Processing TestUser records')
      
      content = fresh_output.string
      
      expect(content).to include('25')
      expect(content).to include('TestUser')
    end

    it 'shows percentage completion' do
      fresh_output = StringIO.new
      fresh_tracker = described_class.new(output: fresh_output)
      fresh_tracker.start_extraction(100)
      
      fresh_tracker.update_progress(50, 'Processing records')
      
      content = fresh_output.string
      
      expect(content).to include('50.0%')
    end

    it 'handles zero total gracefully' do
      fresh_output = StringIO.new
      zero_tracker = described_class.new(output: fresh_output)
      zero_tracker.start_extraction(0)
      
      expect { zero_tracker.update_progress(0, 'No records') }.not_to raise_error
    end
  end

  describe '#complete_extraction' do
    before do
      tracker.start_extraction(100)
    end

    it 'displays completion message' do
      tracker.complete_extraction(100, 1.5)
      
      expect(output.string).to include('Extraction completed')
      expect(output.string).to include('100')
      expect(output.string).to include('1.5')
    end

    it 'shows records per second' do
      tracker.complete_extraction(200, 2.0)
      
      expect(output.string).to include('100.0 records/sec')
    end

    it 'handles zero time duration' do
      expect { tracker.complete_extraction(100, 0) }.not_to raise_error
    end
  end

  describe '#start_import' do
    it 'displays import start message' do
      tracker.start_import(50)
      
      expect(output.string).to include('Starting import')
      expect(output.string).to include('50')
    end
  end

  describe '#complete_import' do
    before do
      tracker.start_import(50)
    end

    it 'displays import completion message' do
      tracker.complete_import(50, 0.8)
      
      expect(output.string).to include('Import completed')
      expect(output.string).to include('50')
      expect(output.string).to include('0.8')
    end
  end

  describe '#log_model_progress' do
    it 'tracks progress by model' do
      tracker.log_model_progress('TestOrder', 5, 10)
      expect(tracker.model_progress['TestOrder']).to eq(
        current: 5,
        total: 10,
        percentage: 50
      )
    end

    it 'updates existing model progress' do
      tracker.log_model_progress('TestOrder', 5, 10)
      tracker.log_model_progress('TestOrder', 8, 10)
      expect(tracker.model_progress['TestOrder']).to eq(
        current: 8,
        total: 10,
        percentage: 80
      )
    end
  end

  describe '#log_error' do
    it 'displays error messages prominently' do
      tracker.log_error('Test error message')
      
      expect(output.string).to include('ERROR')
      expect(output.string).to include('Test error message')
    end

    it 'works even when tracker is disabled' do
      disabled_tracker = described_class.new(enabled: false, output: output)
      disabled_tracker.log_error('Important error')
      
      expect(output.string).to include('ERROR')
      expect(output.string).to include('Important error')
    end
  end

  describe '#log_warning' do
    it 'displays warning messages' do
      tracker.log_warning('Test warning message')
      
      expect(output.string).to include('WARNING')
      expect(output.string).to include('Test warning message')
    end
  end

  describe '#log_info' do
    it 'displays info messages when enabled' do
      tracker.log_info('Test info message')
      
      expect(output.string).to include('Test info message')
    end

    it 'suppresses info messages when disabled' do
      disabled_tracker = described_class.new(enabled: false, output: output)
      disabled_tracker.log_info('This should not appear')
      
      expect(output.string).to be_empty
    end
  end

  describe 'progress formatting' do
    it 'formats large numbers with commas' do
      tracker.start_extraction(1_000_000)
      
      expect(output.string).to include('1,000,000')
    end

    it 'handles decimal numbers in timing' do
      tracker.start_extraction(100)
      tracker.complete_extraction(100, 1.234567)
      
      # Should round to reasonable precision
      expect(output.string).to include('1.23')
      expect(output.string).not_to include('1.234567')
    end

    it 'shows appropriate time units' do
      fresh_output = StringIO.new
      fresh_tracker = described_class.new(output: fresh_output)
      fresh_tracker.start_extraction(100)
      
      # Test seconds
      fresh_tracker.complete_extraction(100, 45.0)
      
      # Test minutes
      fresh_tracker.complete_extraction(100, 125.0)
      
      content = fresh_output.string
      
      expect(content).to include('2m 5s')
    end
  end

  describe 'thread safety' do
    it 'handles concurrent updates safely' do
      tracker.start_extraction(1000)
      
      threads = []
      10.times do |i|
        threads << Thread.new do
          10.times do |j|
            tracker.update_progress(i * 10 + j, "Thread #{i} progress #{j}")
            sleep(0.001) # Small delay to encourage race conditions
          end
        end
      end
      
      threads.each(&:join)
      
      # Should complete without errors
      tracker.complete_extraction(1000, 1.0)
      
      expect(output.string).not_to be_empty
    end
  end

  describe 'memory usage tracking' do
    it 'can track memory usage during operations' do
      # Mock memory tracking
      allow(tracker).to receive(:current_memory_usage).and_return(45.5)
      
      tracker.log_memory_usage
      
      content = output.string
      
      expect(content).to include('Memory')
      expect(content).to include('45.5')
    end
  end

  describe 'integration with real operations' do
    it 'provides useful feedback during actual extraction' do
      # Simulate a real extraction process
      tracker.start_extraction(5)
      
      %w[TestUser TestPartner TestAddress TestOrder TestProduct].each_with_index do |model, index|
        tracker.update_progress(index + 1, "Extracting #{model}")
        tracker.log_model_progress(model, 1, 1)
      end
      
      tracker.complete_extraction(5, 0.5)
      
      expect(output.string).to include('Starting extraction')
      expect(output.string).to include('TestUser')
      expect(output.string).to include('TestOrder')
      expect(output.string).to include('Extraction completed')
      expect(output.string).to include('10.0 records/sec')
    end

    it 'provides useful feedback during actual import' do
      # Simulate a real import process
      tracker.start_import(3)
      
      ['TestUser', 'TestOrder', 'TestProduct'].each_with_index do |model, index|
        tracker.update_progress(index + 1, "Importing #{model}")
        tracker.log_model_progress(model, 1, 1)
      end
      
      tracker.complete_import(3, 0.3)
      
      expect(output.string).to include('Starting import')
      expect(output.string).to include('Import completed')
      expect(output.string).to include('10.0 records/sec')
    end
  end

  describe 'error scenarios' do
    it 'handles output stream errors gracefully' do
      # Mock a closed or failed output stream
      failing_output = double('output')
      allow(failing_output).to receive(:puts).and_raise(IOError.new('Stream closed'))
      allow(failing_output).to receive(:print).and_raise(IOError.new('Stream closed'))
      
      failing_tracker = described_class.new(output: failing_output)
      
      # Should not raise errors, just silently fail
      expect { failing_tracker.start_extraction(100) }.not_to raise_error
      expect { failing_tracker.update_progress(50, 'test') }.not_to raise_error
      expect { failing_tracker.log_error('test error') }.not_to raise_error
    end
  end

  describe '#increment' do
    it 'increments processed records' do
      tracker.increment
      expect(tracker.processed_records).to eq(1)
    end

    it 'updates progress percentage' do
      tracker = described_class.new(total_records: 100)
      tracker.increment
      expect(tracker.progress_percentage).to eq(1)
    end

    it 'handles zero total records' do
      expect(tracker.progress_percentage).to eq(0)
    end
  end

  describe '#elapsed_time' do
    it 'returns elapsed time in seconds' do
      tracker.start
      sleep(1)
      expect(tracker.elapsed_time).to be >= 1
    end
  end

  describe '#estimated_time_remaining' do
    it 'returns estimated time remaining' do
      tracker = described_class.new(total_records: 100)
      tracker.start
      tracker.increment
      expect(tracker.estimated_time_remaining).to be >= 0
    end
  end

  describe '#records_per_second' do
    it 'returns records processed per second' do
      tracker = described_class.new(total_records: 100)
      tracker.start
      tracker.increment
      expect(tracker.records_per_second).to be >= 0
    end
  end

  describe '#to_s' do
    it 'returns string representation' do
      tracker = described_class.new(total_records: 100)
      tracker.start
      tracker.increment
      expect(tracker.to_s).to include('1.0%')
    end
  end

  describe '#to_json' do
    it 'returns JSON representation' do
      tracker = described_class.new(total_records: 100)
      tracker.start
      tracker.increment
      json = JSON.parse(tracker.to_json)
      expect(json).to include(
        'total_records' => 100,
        'processed_records' => 1
      )
    end
  end

  describe '#reset' do
    it 'resets all counters' do
      tracker = described_class.new(total_records: 100)
      tracker.start
      tracker.increment
      tracker.log_model_progress('TestOrder', 1)
      tracker.reset
      expect(tracker.processed_records).to eq(0)
      expect(tracker.model_progress).to eq({})
      expect(tracker.start_time).to be_nil
    end
  end

  describe '#complete?' do
    it 'returns true when all records are processed' do
      tracker = described_class.new(total_records: 1)
      tracker.increment
      expect(tracker.complete?).to be true
    end

    it 'returns false when not all records are processed' do
      tracker = described_class.new(total_records: 2)
      tracker.increment
      expect(tracker.complete?).to be false
    end
  end

  describe '#log_progress_to_io' do
    let(:io) { StringIO.new }

    it 'logs progress to IO' do
      tracker = described_class.new(total_records: 100)
      tracker.start
      tracker.increment
      tracker.log_progress_to_io(io)
      expect(io.string).to include('1.0%')
    end

    it 'includes timing information' do
      tracker = described_class.new(total_records: 100)
      tracker.start
      tracker.increment
      tracker.log_progress_to_io(io)
      expect(io.string).to include('Elapsed')
      expect(io.string).to include('Remaining')
    end

    it 'includes model progress' do
      tracker = described_class.new(total_records: 100)
      tracker.start
      tracker.log_model_progress('TestOrder', 1)
      tracker.log_progress_to_io(io)
      expect(io.string).to include('TestOrder')
    end
  end
end 