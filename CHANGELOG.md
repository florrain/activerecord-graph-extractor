# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-01-28

### Added
- Initial release of ActiveRecord Graph Extractor
- Core extraction functionality with relationship traversal
- Smart dependency resolution for import order
- Beautiful CLI with progress visualization
- Memory-efficient streaming for large datasets
- Comprehensive configuration options
- Transaction-safe imports with rollback
- Support for circular reference detection and handling
- Primary key mapping and foreign key resolution
- JSON validation and error handling
- Support for polymorphic associations
- Batch processing for performance
- Progress tracking and callbacks
- CLI commands: extract, import, analyze
- Comprehensive documentation and examples

### Features
- **Extractor**: Complete object graph extraction with configurable depth and relationships
- **Importer**: Dependency-aware import with primary key remapping
- **CLI**: Beautiful terminal interface with colors, progress bars, and spinners
- **Configuration**: Highly configurable traversal rules and import options
- **Error Handling**: Comprehensive error handling with detailed error messages
- **Performance**: Memory-efficient processing with streaming JSON support
- **Safety**: Transaction-wrapped imports with automatic rollback on errors 