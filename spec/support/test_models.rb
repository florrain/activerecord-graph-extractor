# frozen_string_literal: true

# Test models that mimic the structure of Order and related models
class TestUser < ActiveRecord::Base
  self.table_name = 'test_users'
  
  has_many :test_orders
  has_many :test_addresses
  has_one :test_profile
  has_many :test_history_records, as: :recordable
  belongs_to :test_order, optional: true
  
  validates :email, presence: true
end

class TestPartner < ActiveRecord::Base
  self.table_name = 'test_partners'
  
  has_many :test_orders
end

class TestAddress < ActiveRecord::Base
  self.table_name = 'test_addresses'
  
  belongs_to :test_user
  has_many :test_orders
end

class TestProfile < ActiveRecord::Base
  self.table_name = 'test_profiles'
  
  belongs_to :test_user
end

class TestOrder < ActiveRecord::Base
  self.table_name = 'test_orders'
  
  belongs_to :test_user
  belongs_to :test_partner
  belongs_to :test_address
  has_many :test_products
  has_many :test_admin_actions
  has_one :test_order_flag
  
  validates :state, inclusion: { in: %w[pending processing completed cancelled] }
end

class TestProduct < ActiveRecord::Base
  self.table_name = 'test_products'
  
  belongs_to :test_order
  belongs_to :test_category, optional: true
  has_many :test_photos
end

class TestCategory < ActiveRecord::Base
  self.table_name = 'test_categories'
  
  has_many :test_products
end

class TestPhoto < ActiveRecord::Base
  self.table_name = 'test_photos'
  
  belongs_to :test_product
end

class TestAdminAction < ActiveRecord::Base
  self.table_name = 'test_admin_actions'
  
  belongs_to :test_order
end

class TestOrderFlag < ActiveRecord::Base
  self.table_name = 'test_order_flags'
  
  belongs_to :test_order
end

# A model with polymorphic associations
class TestHistoryRecord < ActiveRecord::Base
  self.table_name = 'test_history_records'
  
  belongs_to :recordable, polymorphic: true
end

# A model with a broken association to test error handling
class TestBrokenModel < ActiveRecord::Base
  self.table_name = 'test_broken_models'
  
  belongs_to :non_existent_model # This will cause a NameError
end 