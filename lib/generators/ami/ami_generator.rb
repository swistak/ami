class AmiGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('../templates', __FILE__)

  def create_ami_migation
    time = Time.now.utc.strftime("%Y%m%d%H%M%S")
    fname = File.join(Rails.root, "db", "migrate", "#{time}_#{file_name}.rb")
  
    up, down = Ami.group_migration

    create_file fname, Ami.migration_template(file_name, up, down)
  end
end
