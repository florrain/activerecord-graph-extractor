# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ActiveRecordGraphExtractor Error Classes' do
  describe ActiveRecordGraphExtractor::Error do
    it 'is the base error class' do
      expect(described_class).to be < StandardError
    end

    it 'can be raised with a message' do
      expect { raise described_class, 'Test error' }.to raise_error(described_class, 'Test error')
    end
  end

  describe ActiveRecordGraphExtractor::ExtractionError do
    it 'inherits from base Error' do
      expect(described_class).to be < ActiveRecordGraphExtractor::Error
    end

    it 'can be raised during extraction failures' do
      expect { raise described_class, 'Extraction failed' }.to raise_error(described_class, 'Extraction failed')
    end
  end

  describe ActiveRecordGraphExtractor::ImportError do
    it 'inherits from base Error' do
      expect(described_class).to be < ActiveRecordGraphExtractor::Error
    end

    it 'can be raised during import failures' do
      expect { raise described_class, 'Import failed' }.to raise_error(described_class, 'Import failed')
    end
  end

  describe ActiveRecordGraphExtractor::SerializationError do
    it 'inherits from base Error' do
      expect(described_class).to be < ActiveRecordGraphExtractor::Error
    end

    it 'can be raised during serialization failures' do
      expect { raise described_class, 'Serialization failed' }.to raise_error(described_class, 'Serialization failed')
    end
  end

  describe ActiveRecordGraphExtractor::CircularDependencyError do
    it 'inherits from base Error' do
      expect(described_class).to be < ActiveRecordGraphExtractor::Error
    end

    it 'can be raised when circular dependencies are detected' do
      expect { raise described_class, 'Circular dependency detected' }.to raise_error(described_class, 'Circular dependency detected')
    end
  end

  describe ActiveRecordGraphExtractor::InvalidRecordError do
    it 'inherits from base Error' do
      expect(described_class).to be < ActiveRecordGraphExtractor::Error
    end

    it 'can be raised for invalid record data' do
      expect { raise described_class, 'Invalid record' }.to raise_error(described_class, 'Invalid record')
    end
  end

  describe 'error hierarchy' do
    it 'allows catching all gem errors with base Error class' do
      extraction_error = nil
      import_error = nil
      
      begin
        raise ActiveRecordGraphExtractor::ExtractionError, 'Test extraction error'
      rescue ActiveRecordGraphExtractor::Error => e
        extraction_error = e
      end
      
      begin
        raise ActiveRecordGraphExtractor::ImportError, 'Test import error'
      rescue ActiveRecordGraphExtractor::Error => e
        import_error = e
      end
      
      expect(extraction_error).to be_a(ActiveRecordGraphExtractor::ExtractionError)
      expect(import_error).to be_a(ActiveRecordGraphExtractor::ImportError)
    end
  end
end 