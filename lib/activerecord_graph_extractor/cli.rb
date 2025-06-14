# frozen_string_literal: true

require 'thor'
require 'tty-progressbar'
require 'tty-spinner'
require 'tty-tree'
require 'pastel'
require 'tty-prompt'

module ActiveRecordGraphExtractor
  class CLI < Thor
    include Thor::Actions

    def self.exit_on_failure?
      true
    end

    desc "version", "Show version information"
    def version
      puts "ActiveRecord Graph Extractor v#{ActiveRecordGraphExtractor::VERSION}"
    end

    desc "extract MODEL_CLASS ID", "Extract a record and its relationships to JSON"
    option :output, aliases: :o, required: true, desc: "Output file path"
    option :max_depth, type: :numeric, default: 5, desc: "Maximum relationship depth"
    option :include_relationships, type: :array, desc: "Specific relationships to include"
    option :exclude_relationships, type: :array, desc: "Relationships to exclude"
    option :include_models, type: :array, desc: "Specific models to include"
    option :exclude_models, type: :array, desc: "Models to exclude"
    option :batch_size, type: :numeric, default: 1000, desc: "Batch size for processing"
    option :progress, type: :boolean, default: false, desc: "Show progress visualization"
    option :show_graph, type: :boolean, default: false, desc: "Show dependency graph"
    option :stream, type: :boolean, default: false, desc: "Use streaming JSON for large datasets"
    
    def extract(model_class_name, id)
      setup_colors
      
      begin
        model_class = model_class_name.constantize
        object = model_class.find(id)
      rescue NameError
        error_exit("Model #{model_class_name} not found")
      rescue ActiveRecord::RecordNotFound
        error_exit("#{model_class_name} with ID #{id} not found")
      end

      config = build_config_from_options(options)
      
      if options[:progress]
        config[:on_progress] = method(:handle_progress_update)
        setup_progress_bars
      end

      @pastel.bright_blue("🔍 Analyzing relationships...")
      puts

      extractor = Extractor.new(root_object: object, config: config)
      
      if options[:show_graph]
        show_dependency_graph(extractor)
      end

      result = nil
      with_spinner("Extracting records") do |spinner|
        result = extractor.extract_to_file(options[:output])
        spinner.success("(#{result.duration_human})")
      end

      print_extraction_summary(result)
      
    rescue => e
      error_exit("Extraction failed: #{e.message}")
    end

    desc "import FILE", "Import records from a JSON file"
    option :batch_size, type: :numeric, default: 1000, desc: "Batch size for processing"
    option :skip_validations, type: :boolean, default: false, desc: "Skip ActiveRecord validations"
    option :dry_run, type: :boolean, default: false, desc: "Preview import without saving"
    option :progress, type: :boolean, default: false, desc: "Show progress visualization"
    option :show_graph, type: :boolean, default: false, desc: "Show dependency graph during import"
    
    def import(file_path)
      setup_colors
      
      unless File.exist?(file_path)
        error_exit("File not found: #{file_path}")
      end

      config = build_config_from_options(options)
      
      if options[:progress]
        config[:on_progress] = method(:handle_import_progress_update)
        setup_import_progress_bars
      end

      importer = Importer.new(config: config)
      
      result = nil
      if options[:dry_run]
        @pastel.yellow("🔍 Performing dry run...")
        puts
      else
        @pastel.bright_blue("📦 Importing records...")
        puts
      end

      with_spinner("Processing import") do |spinner|
        result = importer.import_from_file(file_path)
        spinner.success("(#{result.duration_human})")
      end

      print_import_summary(result)
      
    rescue => e
      error_exit("Import failed: #{e.message}")
    end

    desc "analyze FILE", "Analyze a JSON export file"
    def analyze(file_path)
      setup_colors
      
      unless File.exist?(file_path)
        error_exit("File not found: #{file_path}")
      end

      serializer = JSONSerializer.new
      
      data = nil
      with_spinner("Loading file") do |spinner|
        data = serializer.deserialize_from_file(file_path)
        spinner.success
      end

      print_analysis(data, file_path)
    end

    desc "extract_to_s3 MODEL_CLASS ID", "Extract a record and upload directly to S3"
    option :bucket, aliases: :b, required: true, desc: "S3 bucket name"
    option :key, aliases: :k, desc: "S3 object key (auto-generated if not provided)"
    option :region, default: 'us-east-1', desc: "AWS region"
    option :max_depth, type: :numeric, default: 5, desc: "Maximum relationship depth"
    option :include_relationships, type: :array, desc: "Specific relationships to include"
    option :exclude_relationships, type: :array, desc: "Relationships to exclude"
    option :include_models, type: :array, desc: "Specific models to include"
    option :exclude_models, type: :array, desc: "Models to exclude"
    option :progress, type: :boolean, default: false, desc: "Show progress visualization"
    
    def extract_to_s3(model_class_name, id)
      setup_colors
      
      begin
        model_class = model_class_name.constantize
        object = model_class.find(id)
      rescue NameError
        error_exit("Model #{model_class_name} not found")
      rescue ActiveRecord::RecordNotFound
        error_exit("#{model_class_name} with ID #{id} not found")
      end

      @pastel.bright_blue("🔍 Extracting and uploading to S3...")
      puts

      extractor = Extractor.new
      extraction_options = build_extraction_options_from_options(options)
      
      result = nil
      with_spinner("Extracting and uploading") do |spinner|
        result = extractor.extract_and_upload_to_s3(
          object,
          bucket_name: options[:bucket],
          s3_key: options[:key],
          region: options[:region],
          options: extraction_options
        )
        spinner.success
      end

      print_s3_extraction_summary(result)
      
    rescue => e
      error_exit("S3 extraction failed: #{e.message}")
    end

    desc "s3_list", "List extraction files in S3 bucket"
    option :bucket, aliases: :b, required: true, desc: "S3 bucket name"
    option :prefix, aliases: :p, desc: "S3 key prefix to filter results"
    option :region, default: 'us-east-1', desc: "AWS region"
    option :max_keys, type: :numeric, default: 50, desc: "Maximum number of files to list"
    
    def s3_list
      setup_colors
      
      @pastel.bright_blue("📋 Listing S3 files...")
      puts

      s3_client = S3Client.new(bucket_name: options[:bucket], region: options[:region])
      
      files = nil
      with_spinner("Fetching file list") do |spinner|
        files = s3_client.list_files(
          prefix: options[:prefix],
          max_keys: options[:max_keys]
        )
        spinner.success
      end

      print_s3_file_list(files)
      
    rescue => e
      error_exit("S3 list failed: #{e.message}")
    end

    desc "s3_download S3_KEY", "Download an extraction file from S3"
    option :bucket, aliases: :b, required: true, desc: "S3 bucket name"
    option :output, aliases: :o, desc: "Local output file path"
    option :region, default: 'us-east-1', desc: "AWS region"
    
    def s3_download(s3_key)
      setup_colors
      
      @pastel.bright_blue("⬇️  Downloading from S3...")
      puts

      s3_client = S3Client.new(bucket_name: options[:bucket], region: options[:region])
      
      result = nil
      with_spinner("Downloading file") do |spinner|
        result = s3_client.download_file(s3_key, options[:output])
        spinner.success
      end

      print_s3_download_summary(result)
      
    rescue => e
      error_exit("S3 download failed: #{e.message}")
    end

    desc "dry_run MODEL_CLASS ID", "Analyze what would be extracted without performing the actual extraction"
    option :max_depth, type: :numeric, desc: "Maximum relationship depth to analyze"
    option :output, aliases: :o, desc: "Output file for analysis report (JSON format)"
    
    def dry_run(model_class_name, id)
      setup_colors
      
      @pastel.bright_blue("🔍 Performing dry run analysis...")
      puts
      puts "   Model: #{@pastel.cyan(model_class_name)}"
      puts "   ID: #{@pastel.cyan(id)}"
      puts "   Max Depth: #{@pastel.cyan(options[:max_depth] || 'default')}"
      puts

      begin
        model_class = model_class_name.constantize
        record = model_class.find(id)
        
        extraction_options = build_extraction_options_from_options(options)
        
        extractor = Extractor.new
        analysis = nil
        
        with_spinner("Analyzing object graph") do |spinner|
          analysis = extractor.dry_run(record, extraction_options)
          spinner.success
        end
        
        if options[:output]
          File.write(options[:output], JSON.pretty_generate(analysis))
          puts @pastel.green("📄 Analysis report saved to: #{options[:output]}")
          puts
        end
        
        print_dry_run_analysis(analysis)
        
      rescue NameError => e
        error_exit("Model not found: #{model_class_name}. Make sure the model class exists and is loaded.")
      rescue ActiveRecord::RecordNotFound => e
        error_exit("Record not found: #{model_class_name} with ID #{id}")
      rescue => e
        error_exit("Analysis failed: #{e.message}")
      end
    end

    private

    def setup_colors
      @pastel = Pastel.new
    end

    def build_config_from_options(options)
      config = {}
      
      config[:max_depth] = options[:max_depth] if options[:max_depth]
      config[:include_relationships] = options[:include_relationships] if options[:include_relationships]
      config[:exclude_relationships] = options[:exclude_relationships] if options[:exclude_relationships]
      config[:include_models] = options[:include_models] if options[:include_models]
      config[:exclude_models] = options[:exclude_models] if options[:exclude_models]
      config[:batch_size] = options[:batch_size] if options[:batch_size]
      config[:stream_json] = options[:stream] if options.key?(:stream)
      config[:skip_validations] = options[:skip_validations] if options.key?(:skip_validations)
      config[:dry_run] = options[:dry_run] if options.key?(:dry_run)
      
      config
    end

    def setup_progress_bars
      @model_progress_bars = {}
      @main_progress_bar = nil
    end

    def setup_import_progress_bars
      @import_progress_bars = {}
      @main_import_progress_bar = nil
    end

    def handle_progress_update(stats)
      model = stats[:model]
      phase = stats[:phase]
      
      # Update main progress bar
      if @main_progress_bar
        @main_progress_bar.current = stats[:current]
        @main_progress_bar.total = stats[:total] if stats[:total] > 0
      elsif stats[:total] && stats[:total] > 0
        @main_progress_bar = TTY::ProgressBar.new(
          "#{@pastel.bright_blue('Overall')} [:bar] :percent :current/:total (:rate/s) :eta",
          total: stats[:total],
          bar_format: :block
        )
      end
      
      # Update model-specific progress bar
      if model && stats[:model_progress] && stats[:model_progress][model]
        model_stats = stats[:model_progress][model]
        
        unless @model_progress_bars[model]
          if model_stats[:total] > 0
            color = get_model_color(model)
            @model_progress_bars[model] = TTY::ProgressBar.new(
              "#{@pastel.decorate(model.ljust(12), color)} [:bar] :percent (:current/:total)",
              total: model_stats[:total],
              bar_format: :block
            )
          end
        end
        
        if @model_progress_bars[model]
          @model_progress_bars[model].current = model_stats[:current]
          
          if stats[:completed]
            @model_progress_bars[model].finish
            @model_progress_bars[model] = @pastel.green("#{model.ljust(12)} ✅ Complete")
          end
        end
      end
    end

    def handle_import_progress_update(stats)
      phase = stats[:phase]
      
      case phase
      when "Importing records"
        handle_progress_update(stats)
      else
        # Handle other phases
        if stats[:total] && stats[:total] > 0
          percentage = (stats[:current].to_f / stats[:total] * 100).round(1)
          print "\r#{@pastel.bright_blue(phase)}: #{percentage}%"
        end
      end
    end

    def get_model_color(model)
      colors = [:cyan, :magenta, :yellow, :green, :red, :blue]
      colors[model.hash % colors.size]
    end

    def show_dependency_graph(extractor)
      # This would require access to the dependency graph from the extractor
      # For now, show a simple tree structure
      puts @pastel.bright_blue("📊 Dependency Analysis")
      puts
      
      # Sample tree structure - in real implementation, this would be built from actual data
      tree_data = {
        "Order (root)" => {
          "User" => {},
          "Partner" => {},
          "Products" => {
            "Photos" => {},
            "Categories" => {}
          },
          "Address" => {}
        }
      }
      
      tree = TTY::Tree.new(tree_data)
      puts tree.render
      puts
    end

    def with_spinner(message)
      spinner = TTY::Spinner.new("[:spinner] #{message}...", format: :dots)
      spinner.auto_spin
      
      result = yield(spinner)
      
      spinner.stop
      result
    end

    def print_extraction_summary(result)
      puts
      puts @pastel.bright_green("✅ Extraction completed successfully!")
      puts
      puts "📊 " + @pastel.bold("Summary:")
      puts "   Total records: #{@pastel.cyan(result.total_records)}"
      puts "   Models: #{@pastel.cyan(result.models.join(', '))}"
      puts "   File size: #{@pastel.cyan(result.file_size_human)}"
      puts "   Duration: #{@pastel.cyan(result.duration_human)}"
      puts "   Output: #{@pastel.cyan(result.file_path)}"
      puts
    end

    def print_import_summary(result)
      puts
      
      if result.dry_run
        puts @pastel.bright_yellow("🔍 Dry run completed successfully!")
      else
        puts @pastel.bright_green("✅ Import completed successfully!")
      end
      
      puts
      puts "📊 " + @pastel.bold("Summary:")
      puts "   Total records: #{@pastel.cyan(result.total_records)}"
      puts "   Models imported: #{@pastel.cyan(result.models_imported.join(', '))}"
      puts "   Duration: #{@pastel.cyan(result.duration_human)}"
      puts "   Speed: #{@pastel.cyan("#{result.records_per_second} records/sec")}"
      
      if result.mapping_statistics
        puts "   ID mappings: #{@pastel.cyan(result.mapping_statistics[:total_mappings])}"
      end
      
      puts
    end

    def print_analysis(data, file_path)
      metadata = data['metadata']
      records = data['records']
      
      puts
      puts @pastel.bright_blue("📋 File Analysis: #{File.basename(file_path)}")
      puts
      
      puts @pastel.bold("Metadata:")
      puts "   Root model: #{@pastel.cyan(metadata['root_model'])}"
      puts "   Root ID: #{@pastel.cyan(metadata['root_id'])}"
      puts "   Extracted: #{@pastel.cyan(metadata['extracted_at'])}"
      puts "   Schema version: #{@pastel.cyan(metadata['schema_version'])}"
      puts "   Total records: #{@pastel.cyan(metadata['total_records'])}"
      puts
      
      puts @pastel.bold("Models and record counts:")
      metadata['model_counts'].each do |model, count|
        puts "   #{model.ljust(20)}: #{@pastel.cyan(count)}"
      end
      puts
      
      file_size = File.size(file_path)
      if file_size < 1024 * 1024
        size_human = "#{(file_size / 1024.0).round(1)} KB"
      else
        size_human = "#{(file_size / (1024.0 * 1024)).round(1)} MB"
      end
      
      puts @pastel.bold("File information:")
      puts "   Size: #{@pastel.cyan(size_human)}"
      puts "   Path: #{@pastel.cyan(file_path)}"
      puts
    end

    def build_extraction_options_from_options(options)
      extraction_options = {}
      extraction_options[:max_depth] = options[:max_depth] if options[:max_depth]
      extraction_options[:include_relationships] = options[:include_relationships] if options[:include_relationships]
      extraction_options[:exclude_relationships] = options[:exclude_relationships] if options[:exclude_relationships]
      extraction_options[:include_models] = options[:include_models] if options[:include_models]
      extraction_options[:exclude_models] = options[:exclude_models] if options[:exclude_models]
      extraction_options
    end

    def print_s3_extraction_summary(result)
      puts
      puts @pastel.bright_green("✅ S3 extraction completed successfully!")
      puts
      puts "📊 " + @pastel.bold("Summary:")
      puts "   Total records: #{@pastel.cyan(result['metadata']['total_records'])}"
      puts "   Models: #{@pastel.cyan(result['metadata']['models_extracted'].join(', '))}"
      puts "   Duration: #{@pastel.cyan("#{result['metadata']['duration_seconds']}s")}"
      puts
      puts "☁️  " + @pastel.bold("S3 Upload:")
      puts "   Bucket: #{@pastel.cyan(result['s3_upload'][:bucket])}"
      puts "   Key: #{@pastel.cyan(result['s3_upload'][:key])}"
      puts "   Size: #{@pastel.cyan(format_file_size(result['s3_upload'][:size]))}"
      puts "   URL: #{@pastel.cyan(result['s3_upload'][:url])}"
      puts
    end

    def print_s3_file_list(files)
      puts
      if files.empty?
        puts @pastel.yellow("No files found")
        return
      end

      puts @pastel.bright_blue("📋 S3 Files (#{files.size} found):")
      puts
      
      files.each do |file|
        puts "#{@pastel.cyan(file[:key])}"
        puts "   Size: #{@pastel.dim(format_file_size(file[:size]))}"
        puts "   Modified: #{@pastel.dim(file[:last_modified].strftime('%Y-%m-%d %H:%M:%S'))}"
        puts
      end
    end

    def print_s3_download_summary(result)
      puts
      puts @pastel.bright_green("✅ S3 download completed successfully!")
      puts
      puts "📊 " + @pastel.bold("Summary:")
      puts "   S3 Key: #{@pastel.cyan(result[:key])}"
      puts "   Local Path: #{@pastel.cyan(result[:local_path])}"
      puts "   Size: #{@pastel.cyan(format_file_size(result[:size]))}"
      puts
    end

    def format_file_size(size_bytes)
      if size_bytes < 1024
        "#{size_bytes} B"
      elsif size_bytes < 1024 * 1024
        "#{(size_bytes / 1024.0).round(1)} KB"
      elsif size_bytes < 1024 * 1024 * 1024
        "#{(size_bytes / (1024.0 * 1024)).round(1)} MB"
      else
        "#{(size_bytes / (1024.0 * 1024 * 1024)).round(1)} GB"
      end
    end

    def print_dry_run_analysis(analysis)
      puts
      puts @pastel.bright_green("✅ Dry run analysis completed!")
      puts
      
      # Basic info
      puts "📊 " + @pastel.bold("Analysis Summary:")
      puts "   Analysis time: #{@pastel.cyan("#{analysis['analysis_time']} seconds")}"
      puts "   Root objects: #{@pastel.cyan(analysis['root_objects']['count'])}"
      puts "   Models involved: #{@pastel.cyan(analysis['extraction_scope']['total_models'])}"
      puts "   Total estimated records: #{@pastel.cyan(analysis['extraction_scope']['total_estimated_records'].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse)}"
      puts "   Estimated file size: #{@pastel.cyan(analysis['estimated_file_size']['human_readable'])}"
      puts
      
      # Performance estimates
      perf = analysis['performance_estimates']
      puts "⏱️  " + @pastel.bold("Performance Estimates:")
      puts "   Extraction time: #{@pastel.cyan(perf['estimated_extraction_time_human'])}"
      puts "   Memory usage: #{@pastel.cyan(perf['estimated_memory_usage_human'])}"
      puts
      
      # Model breakdown
      puts "📋 " + @pastel.bold("Records by Model:")
      analysis['estimated_counts_by_model'].each do |model, count|
        percentage = (count.to_f / analysis['extraction_scope']['total_estimated_records'] * 100).round(1)
        puts "   #{model.ljust(20)} #{@pastel.cyan(count.to_s.rjust(8))} (#{percentage}%)"
      end
      puts
      
      # Depth analysis
      if analysis['depth_analysis'].any?
        puts "🌳 " + @pastel.bold("Depth Analysis:")
        analysis['depth_analysis'].each do |depth, models|
          puts "   Level #{depth}: #{@pastel.cyan(models.join(', '))}"
        end
        puts
      end
      
      # Warnings
      if analysis['warnings'].any?
        puts "⚠️  " + @pastel.bold("Warnings:")
        analysis['warnings'].each do |warning|
          color = case warning['severity']
                  when 'high' then :red
                  when 'medium' then :yellow
                  else :white
                  end
          puts "   #{@pastel.decorate("#{warning['type'].upcase}:", color)} #{warning['message']}"
        end
        puts
      end
      
      # Recommendations
      if analysis['recommendations'].any?
        puts "💡 " + @pastel.bold("Recommendations:")
        analysis['recommendations'].each do |rec|
          puts "   #{@pastel.yellow("#{rec['type'].upcase}:")} #{rec['message']}"
          puts "   #{@pastel.dim("→ #{rec['action']}")}"
          puts
        end
      end
      
      # Circular references
      if analysis['relationship_analysis']['circular_references_count'] > 0
        puts "🔄 " + @pastel.bold("Circular References Detected:")
        analysis['relationship_analysis']['circular_references'].each do |ref|
          puts "   #{@pastel.yellow(ref['path'])} (depth #{ref['depth']})"
        end
        puts
      end
    end

    def error_exit(message)
      puts @pastel.red("❌ Error: #{message}")
      exit(1)
    end
  end
end 