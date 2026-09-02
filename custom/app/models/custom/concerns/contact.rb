# Injetado em Contact por Contact.include_mod_with('Concerns::Contact').
module Custom::Concerns::Contact
  extend ActiveSupport::Concern

  included do
    has_many :funnel_task_contacts, class_name: 'Funnel::TaskContact', dependent: :destroy
    has_many :funnel_tasks, through: :funnel_task_contacts, source: :task
  end
end
