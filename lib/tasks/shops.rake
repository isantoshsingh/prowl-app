# frozen_string_literal: true

namespace :shops do
  desc "Grant billing exemption to a shop"
  task :exempt, [:domain, :reason] => :environment do |_t, args|
    unless args[:domain]
      puts "Usage: rake shops:exempt DOMAIN=shop.myshopify.com REASON='Development Partner'"
      exit 1
    end
    
    shop = Shop.find_by(shopify_domain: args[:domain])
    
    unless shop
      puts "Error: Shop '#{args[:domain]}' not found"
      exit 1
    end
    
    reason = args[:reason] || "Billing exempt"
    
    shop.update!(
      billing_exempt: true,
      exemption_reason: reason
    )
    
    puts "✓ Billing exemption granted to #{shop.shopify_domain}"
    puts "  Reason: #{reason}"
  end
  
  desc "Revoke billing exemption from a shop"
  task :unexempt, [:domain] => :environment do |_t, args|
    unless args[:domain]
      puts "Usage: rake shops:unexempt DOMAIN=shop.myshopify.com"
      exit 1
    end
    
    shop = Shop.find_by(shopify_domain: args[:domain])
    
    unless shop
      puts "Error: Shop '#{args[:domain]}' not found"
      exit 1
    end
    
    shop.update!(
      billing_exempt: false,
      exemption_reason: nil
    )
    
    puts "✓ Billing exemption revoked for #{shop.shopify_domain}"
  end
  
  desc "List all exempt shops"
  task list_exempt: :environment do
    exempt_shops = Shop.where(billing_exempt: true)
    
    if exempt_shops.empty?
      puts "No exempt shops found"
    else
      puts "Exempt shops (#{exempt_shops.count}):"
      puts ""
      exempt_shops.each do |shop|
        puts "  #{shop.shopify_domain}"
        puts "  Reason: #{shop.exemption_reason || 'No reason specified'}"
        puts "  ---"
      end
    end
  end
end
