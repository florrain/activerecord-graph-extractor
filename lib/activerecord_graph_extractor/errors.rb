# frozen_string_literal: true

module ActiveRecordGraphExtractor
  # Base error class for all ActiveRecordGraphExtractor errors
  class Error < StandardError; end

  # Raised when extraction fails
  class ExtractionError < Error; end

  # Raised when import fails
  class ImportError < Error; end

  # Raised when serialization/deserialization fails
  class SerializationError < Error; end

  # Raised when circular dependencies are detected
  class CircularDependencyError < Error; end

  # Raised when record data is invalid
  class InvalidRecordError < Error; end

  class ConfigurationError < Error; end

  class ValidationError < ImportError; end

  class DependencyError < ImportError; end

  class FileError < Error; end

  class JSONError < Error; end

  class S3Error < Error; end
end 