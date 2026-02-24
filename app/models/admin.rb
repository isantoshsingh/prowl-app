# frozen_string_literal: true

class Admin < ApplicationRecord
  devise :database_authenticatable, :rememberable, :validatable,
         :timeoutable, :lockable
end
