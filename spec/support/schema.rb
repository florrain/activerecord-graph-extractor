# frozen_string_literal: true

class CreateTestSchema < ActiveRecord::Migration[6.0]
  def change
    create_table :test_users do |t|
      t.string :email
      t.string :first_name
      t.string :last_name
      t.references :test_order
    end

    create_table :test_partners do |t|
      t.string :name
      t.string :partner_type
    end

    create_table :test_addresses do |t|
      t.references :test_user
      t.string :street
      t.string :city
      t.string :state
      t.string :zip
    end

    create_table :test_profiles do |t|
      t.references :test_user
      t.text :bio
      t.string :phone
    end

    create_table :test_orders do |t|
      t.references :test_user
      t.references :test_partner
      t.references :test_address
      t.string :state
      t.decimal :total_amount, precision: 10, scale: 2
      t.boolean :is_gift, default: false
    end

    create_table :test_products do |t|
      t.references :test_order
      t.references :test_category
      t.string :product_number
      t.string :state
      t.decimal :price, precision: 10, scale: 2
    end

    create_table :test_categories do |t|
      t.string :name
    end

    create_table :test_photos do |t|
      t.references :test_product
      t.string :url
      t.string :photo_type
    end

    create_table :test_admin_actions do |t|
      t.references :test_order
      t.string :action_type
      t.text :description
    end

    create_table :test_order_flags do |t|
      t.references :test_order
      t.string :flag_type
      t.text :reason
    end

    create_table :test_history_records do |t|
      t.references :recordable, polymorphic: true
      t.string :event_type
      t.json :data
    end

    create_table :test_broken_models do |t|
      t.integer :non_existent_model_id
      t.string :name
    end
  end
end 