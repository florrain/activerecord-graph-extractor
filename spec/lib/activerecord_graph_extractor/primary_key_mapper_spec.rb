# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecordGraphExtractor::PrimaryKeyMapper do
  let(:mapper) { described_class.new }

  describe '#initialize' do
    it 'accepts valid strategies' do
      expect { described_class.new(:preserve_original) }.not_to raise_error
      expect { described_class.new(:generate_new) }.not_to raise_error
    end

    it 'raises error for invalid strategy' do
      expect { described_class.new(:invalid) }.to raise_error(ArgumentError)
    end
  end

  describe '#add_mapping and #get_mapping' do
    it 'stores and retrieves mappings' do
      mapper.add_mapping('TestUser', 1, 100)
      mapper.add_mapping('TestOrder', 5, 500)

      expect(mapper.get_mapping('TestUser', 1)).to eq(100)
      expect(mapper.get_mapping('TestOrder', 5)).to eq(500)
      expect(mapper.get_mapping('TestUser', 999)).to be_nil
    end

    it 'handles string and symbol model names' do
      mapper.add_mapping(:TestUser, 1, 100)
      expect(mapper.get_mapping('TestUser', 1)).to eq(100)
      expect(mapper.get_mapping(:TestUser, 1)).to eq(100)
    end
  end

  describe '#map_foreign_key' do
    before do
      mapper.add_mapping('TestUser', 1, 100)
      mapper.add_mapping('TestOrder', 5, 500)
    end

    it 'maps foreign key references' do
      expect(mapper.map_foreign_key('test_user_id', 1)).to eq(100)
      expect(mapper.map_foreign_key('test_order_id', 5)).to eq(500)
    end

    it 'returns original value if no mapping exists' do
      expect(mapper.map_foreign_key('test_user_id', 999)).to eq(999)
    end

    it 'handles nil values' do
      expect(mapper.map_foreign_key('test_user_id', nil)).to be_nil
    end

    it 'returns original value for non-foreign key columns' do
      expect(mapper.map_foreign_key('email', 'test@example.com')).to eq('test@example.com')
    end
  end

  describe '#get_all_mappings' do
    it 'returns all mappings' do
      mapper.add_mapping('TestUser', 1, 100)
      mapper.add_mapping('TestOrder', 5, 500)

      mappings = mapper.get_all_mappings
      expect(mappings).to eq({
        'TestUser' => { 1 => 100 },
        'TestOrder' => { 5 => 500 }
      })
    end

    it 'returns a copy to prevent modification' do
      mapper.add_mapping('TestUser', 1, 100)
      mappings = mapper.get_all_mappings
      mappings['TestUser'] = { 1 => 999 } # Completely replace the hash
      
      # Original mapping should still be intact
      expect(mapper.get_mapping('TestUser', 1)).to eq(100)
    end
  end

  describe '#should_preserve_primary_key?' do
    it 'returns true for preserve_original strategy' do
      preserve_mapper = described_class.new(:preserve_original)
      expect(preserve_mapper.should_preserve_primary_key?).to be(true)
    end

    it 'returns false for generate_new strategy' do
      generate_mapper = described_class.new(:generate_new)
      expect(generate_mapper.should_preserve_primary_key?).to be(false)
    end
  end
end 