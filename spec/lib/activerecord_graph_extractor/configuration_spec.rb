# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::Configuration do
  let(:config) { described_class.new }

  describe '#initialize' do
    it 'sets default values' do
      expect(config.max_depth).to eq(5)
      expect(config.batch_size).to eq(1000)
      expect(config.progress_enabled).to be(true)
      expect(config.stream_json).to be(false)
      expect(config.validate_records).to be(true)
      expect(config.use_transactions).to be(true)
      expect(config.handle_circular_references).to be(true)
      expect(config.skip_missing_models).to be(true)
      expect(config.included_models).to eq([])
      expect(config.excluded_models).to eq([])
      expect(config.included_relationships).to eq([])
      expect(config.excluded_relationships).to eq([])
      expect(config.custom_serializers).to eq({})
      expect(config.primary_key_strategy).to eq(:generate_new)
    end
  end

  describe '#max_depth=' do
    it 'sets the max depth' do
      config.max_depth = 10
      expect(config.max_depth).to eq(10)
    end

    it 'raises error for invalid values' do
      expect { config.max_depth = -1 }.to raise_error(ArgumentError, 'max_depth must be positive')
      expect { config.max_depth = 0 }.to raise_error(ArgumentError, 'max_depth must be positive')
    end
  end

  describe '#batch_size=' do
    it 'sets the batch size' do
      config.batch_size = 500
      expect(config.batch_size).to eq(500)
    end

    it 'raises error for invalid values' do
      expect { config.batch_size = 0 }.to raise_error(ArgumentError, 'batch_size must be positive')
      expect { config.batch_size = -1 }.to raise_error(ArgumentError, 'batch_size must be positive')
    end
  end

  describe '#primary_key_strategy=' do
    it 'accepts valid strategies' do
      config.primary_key_strategy = :preserve_original
      expect(config.primary_key_strategy).to eq(:preserve_original)

      config.primary_key_strategy = :generate_new
      expect(config.primary_key_strategy).to eq(:generate_new)
    end

    it 'raises error for invalid strategy' do
      expect { config.primary_key_strategy = :invalid }.to raise_error(
        ArgumentError, 'primary_key_strategy must be :preserve_original or :generate_new'
      )
    end
  end

  describe '#include_model' do
    it 'adds model to included_models' do
      config.include_model('TestUser')
      expect(config.included_models).to include('TestUser')
    end

    it 'accepts class as argument' do
      config.include_model(TestUser)
      expect(config.included_models).to include('TestUser')
    end
  end

  describe '#exclude_model' do
    it 'adds model to excluded_models' do
      config.exclude_model('TestUser')
      expect(config.excluded_models).to include('TestUser')
    end

    it 'accepts class as argument' do
      config.exclude_model(TestUser)
      expect(config.excluded_models).to include('TestUser')
    end
  end

  describe '#include_relationship' do
    it 'adds relationship to included_relationships' do
      config.include_relationship('test_user')
      expect(config.included_relationships).to include('test_user')
    end
  end

  describe '#exclude_relationship' do
    it 'adds relationship to excluded_relationships' do
      config.exclude_relationship('test_user')
      expect(config.excluded_relationships).to include('test_user')
    end
  end

  describe '#add_custom_serializer' do
    it 'adds custom serializer' do
      serializer = proc { |obj| { id: obj.id } }
      config.add_custom_serializer('TestUser', serializer)
      expect(config.custom_serializers['TestUser']).to eq(serializer)
    end

    it 'accepts class as key' do
      serializer = proc { |obj| { id: obj.id } }
      config.add_custom_serializer(TestUser, serializer)
      expect(config.custom_serializers['TestUser']).to eq(serializer)
    end
  end

  describe '#model_included?' do
    context 'when included_models is empty' do
      it 'returns true for any model' do
        expect(config.model_included?('TestUser')).to be(true)
      end
    end

    context 'when included_models has values' do
      before do
        config.include_model('TestUser')
        config.include_model('TestPartner')
      end

      it 'returns true for included models' do
        expect(config.model_included?('TestUser')).to be(true)
        expect(config.model_included?('TestPartner')).to be(true)
      end

      it 'returns false for non-included models' do
        expect(config.model_included?('TestCategory')).to be(false)
      end
    end

    context 'when model is excluded' do
      before do
        config.exclude_model('TestUser')
      end

      it 'returns false for excluded models' do
        expect(config.model_included?('TestUser')).to be(false)
      end
    end
  end

  describe '#relationship_included?' do
    context 'when included_relationships is empty' do
      it 'returns true for any relationship' do
        expect(config.relationship_included?('test_user')).to be(true)
      end
    end

    context 'when included_relationships has values' do
      before do
        config.include_relationship('test_user')
        config.include_relationship('test_products')
      end

      it 'returns true for included relationships' do
        expect(config.relationship_included?('test_user')).to be(true)
        expect(config.relationship_included?('test_products')).to be(true)
      end

      it 'returns false for non-included relationships' do
        expect(config.relationship_included?('test_photos')).to be(false)
      end
    end

    context 'when relationship is excluded' do
      before do
        config.exclude_relationship('test_user')
      end

      it 'returns false for excluded relationships' do
        expect(config.relationship_included?('test_user')).to be(false)
      end
    end
  end

  describe '#configure' do
    it 'yields the configuration for setup' do
      described_class.configure do |config|
        config.max_depth = 3
        config.batch_size = 500
        config.progress_enabled = false
      end

      expect(described_class.configuration.max_depth).to eq(3)
      expect(described_class.configuration.batch_size).to eq(500)
      expect(described_class.configuration.progress_enabled).to be(false)
    end
  end

  describe '#reset!' do
    it 'resets configuration to defaults' do
      config.max_depth = 10
      config.batch_size = 500
      config.include_model('TestUser')

      config.reset!

      expect(config.max_depth).to eq(5)
      expect(config.batch_size).to eq(1000)
      expect(config.included_models).to be_empty
    end
  end
end 