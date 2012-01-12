ActiveRecord::Base.extend(Ami::ClassMethods)

# We need to find a better way to do automigrations.
# In to much cases (rake tasks, generators) ami is trying to automigrate when it should not to.
#
# For now we add *ami!* method to kernel, that should allow easy automigrating
if Rails.env.development? && false
  Ami.ar_migrate!

  ActionDispatch::Callbacks.to_prepare do
    begin
      Ami.automigrate!
    rescue Exception => e
      ActiveRecord::Base.logger.error "Cannot automigrate!: #{e}"
    end
  end
end

Object.class_eval do
  def ami!()
    respond_to?(:reload!) && reload! # Reload classes in console.
    Ami.automigrate!
  end
end
