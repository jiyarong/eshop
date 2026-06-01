class User < ApplicationRecord
  devise :database_authenticatable,
         :recoverable,
         :rememberable,
         :validatable,
         :trackable

  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :feedback_tasks, dependent: :destroy

  validates :active, inclusion: { in: [true, false] }

  def active_for_authentication?
    super && active?
  end

  def inactive_message
    active? ? super : :inactive
  end

  def has_role?(role_code)
    roles.any? { |role| role.code == role_code.to_s }
  end

  def can?(permission)
    roles.any? { |role| role.allows?(permission) }
  end
end
