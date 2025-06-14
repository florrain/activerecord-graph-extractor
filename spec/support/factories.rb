# frozen_string_literal: true

FactoryBot.define do
  factory :test_user do
    first_name { "John" }
    last_name { "Doe" }
    email { "user@example.com" }
  end

  factory :test_partner do
    name { "Partner Company" }
    partner_type { "consignment" }
  end

  factory :test_address do
    test_user
    street { "123 Main St" }
    city { "Anytown" }
    state { "CA" }
    zip { "12345" }
  end

  factory :test_profile do
    test_user
    bio { "User bio" }
    phone { "555-1234" }
  end

  factory :test_order do
    test_user
    test_partner
    test_address
    state { "completed" }
    total_amount { 100.00 }
    is_gift { false }
  end

  factory :test_order_with_relationships, class: 'TestOrder' do
    test_user
    test_partner
    test_address
    state { "completed" }
    total_amount { 100.00 }
    is_gift { false }
    
    after(:create) do |order|
      create(:test_product, test_order: order)
      create(:test_admin_action, test_order: order)
      create(:test_order_flag, test_order: order)
    end
  end

  factory :test_product do
    test_order
    test_category
    product_number { "ITEM001" }
    state { "active" }
    price { 25.00 }
  end

  factory :test_category do
    name { "Electronics" }
  end

  factory :test_photo do
    test_product
    url { "http://example.com/photo.jpg" }
    photo_type { "main" }
  end

  factory :test_admin_action do
    test_order
    action_type { "review" }
    description { "Admin reviewed order" }
  end

  factory :test_order_flag do
    test_order
    flag_type { "suspicious" }
    reason { "Unusual activity detected" }
  end

  factory :test_history_record do
    association :recordable, factory: :test_user
    event_type { "created" }
    data { { "action" => "record_created" } }
  end

  factory :test_broken_model do
    non_existent_model_id { 999 }
    name { "Broken Model" }
  end
end 