module Ami
 class Properties
    attr_accessor :model, :properties

    def initialize(model)
      @model = model
      @properties = {}
    end

    def []=(key, value)
      @properties[key.to_s] = OpenStruct.new(value)
    end

    def [](key)
      @properties[key.to_s]
    end

    def column_keys
      [:type, :null, :limit, :precision, :scale, :default, :primary]
    end

    def defaults(name, type)
      defaults = {
        :null => true, 
        :primary => false,
        :name => name,
        :type => type,
      }
      
      defaults.merge!({
        :id => {:null => false, :primary => true},
      }[name] || {})
      
      defaults.merge!({
        :string => {:limit => 255}
      }[type] || {})

      defaults
    end

    def synced?
      return false unless properties.keys.sort == model.column_names.sort

      cmp = lambda do |column, property| 
        column_keys.all?{|a| column.send(a) == property.send(a) }
      end

      columns.all?{|column| cmp.call(column, properties[column.name]) }
    end

    def diff
      keys = properties.keys | model.column_names

      renames = {}
      changes = []

      keys.each do |k|
        diff = {}
        property, column = properties[k], model.columns_hash[k]

        if !column && property.previously
          prev = property.previously.to_s
          
          if column = model.columns_hash[prev]
            changes << [k, :rename, {:from => prev, :to => k}]
            renames[prev] = k
          end
        end

        if !property 
          next if renames[k]
          column_keys.each{|k| diff[k] = column.send(k) }

          changes << [k, :remove, diff]
        elsif !column
          column_keys.each{|k| diff[k] = property.send(k) }

          changes << [k, :add, diff]
        else
          column_keys.each do |c| 
            from, to = column.send(c), property.send(c)
            diff[c] = {:from => from, :to => to} unless from == to
          end

          changes << [k, :change, diff] if diff.present?
        end
      end

      changes
    end

    def line(column, options={})
      o = {
        :indent => 0,
        :prefix => 'column',
        :width => 20,
        :skip_foreign_keys => true
      }.merge(options)

      foreign_keys = model.reflect_on_all_associations(:belongs_to).map(&:foreign_key)
      defaults = defaults(column.name.to_sym, column.type)

      return if foreign_keys.include?(column.name) && o[:skip_foreign_keys]

      opts = column_keys.
        reject{|c| c == :type }.
        reject{|c| defaults[c] == column.send(c) }.          
        map{|c| ":#{c} => #{column.send(c).inspect}" }

      column_type = column.primary ? :primary_key : column.type

      opts = "%-#{o[:width]}s %-10s %s" % [":#{column.name},", ":#{column_type}#{(opts.present? ? ", " : "")}", opts.join(", ")]

      " " * o[:indent] + "#{o[:prefix]} #{opts}".strip
    end

    def declaration(options={})
      width = columns.map{|c| c.name.length + 2}.max
      columns.map{|column| line(column, :width => width, :indent => 2) }
    end

    def pad(x)
      lambda{|l| " " * x + l}
    end

    def format(*args)
      args.flatten.map(&pad(4)).join("\n")
    end

    def change_migration
      changes_up = []
      changes_down = []
      changes = diff

      width = changes.map{|c, op, diff| c.to_s.length + 2}.max

      changes.each do |column_symbol, op, diff|
        column_name = column_symbol.to_s

        property, column = @properties[column_name], model.columns_hash[column_name]
        column ||= model.columns_hash[property.previously.to_s]

        case op
        when :add    then 
          changes_up   << line(property, :prefix => "t.column", :width => width, :skip_foreign_keys => false)
          changes_down << "t.remove :#{column_name}"
        when :remove then 
          changes_up   << "t.remove :#{column_name}"
          changes_down << line(column,   :prefix => "t.column", :width => width)
        when :change then 
          changes_up   << line(property, :prefix => "t.change", :width => width)
          changes_down << line(column,   :prefix => "t.change", :width => width)
        when :rename then 
          changes_up   << "t.rename :#{diff[:from]}, :#{diff[:to]}" 
          changes_down << "t.rename :#{diff[:to]}, :#{diff[:from]}" 
        end
      end

      up = format([
        "# #{model.name}",
        "change_table '#{model.table_name}' do |t|",
        changes_up.compact.map(&pad(2)),
        "end"
      ])     
      down = format([
        "# #{model.name}",
        "change_table '#{model.table_name}' do |t|",
        changes_down.compact.map(&pad(2)),
        "end"
      ])

      [changes_up.present? && up, changes_down.present? && down]
    end

    def create_migration
      width = properties.map{|name, property| name.length + 2}.length

      has_id = false
      changes = properties.reject{|name, property| (name == "id" && property.primary) ? (has_id = true) : false }

      changes_up = changes.map{|name, property| 
        line(property, :prefix => "t.column", :width => width, :skip_foreign_keys => false) 
      }.compact

      up = format([
        "# #{model.name}",
        "create_table '#{model.table_name}', :id => #{has_id} do |t|",
        changes_up.map(&pad(2)),
        "end"
      ])
     
      down = format([
        "# #{model.name}",
        "drop_table '#{model.table_name}'"
      ])

      [up, down]
    end
  end

  module ClassMethods
    def column(name, type, options={})
      options = properties.defaults(name, type).merge(options)

      self.properties[name] = options
    end

    def belongs_to(name, options={})
      opt = {
        :type => :integer,
        :name => options[:foreign_key] || name.to_s.foreign_key,
        :null => true,
        :primary => false,
      }

      self.properties[opt[:name]] = opt

      super
    end

    def properties
      @ami_properties ||= Properties.new(self)
    end
  end

  module_function

  def models
    base = File.join(Rails.root, 'app', 'models')

    @models ||= Dir.glob(File.join(base, '**/*.rb')).map do |mpath|
      begin
        model = mpath.
          sub(base, '').sub('.rb', '').
          classify.constantize

        model.ancestors.include?(ActiveRecord::Base)
        model.abstract_class ? nil : model
      rescue LoadError
        $stderr.puts "Could not load #{mpath}"
      end
    end.compact
  end

  def migration_template(name, up, down)
<<MIGRATION
class #{name.classify} < ActiveRecord::Migration
  def self.up
#{up.join("\n\n")}
  end

  def self.down
#{down.reverse.join("\n\n")}
  end
end
MIGRATION
  end

  def automigrate!
    models.each do |m|
      m.reset_column_information
    
      if m.table_exists? 
        up, down = m.properties.change_migration
        write_migration([up] || [], [down] || [], "change_#{m.name.underscore}", :run) if up || down
      else 
        up, down = m.properties.create_migration  
        write_migration([up] || [], [down] || [], "create_#{m.name.underscore}", :run) if up || down
      end

      m.reset_column_information
    end

    :done
  end

  def group_migration
    up, down = [], []
    changes = models.
      map{|m| m.table_exists? ? m.properties.change_migration : m.properties.create_migration }.
      each{|m| up << m[0] if m[0].present?; down << m[1] if m[1].present? }

    [up, down]
  end

  def write!(name, run=false)
    up, down = *group_migration
    write_migration(up, down, name, run)
  end

  def ar_migrate!
    ActiveRecord::Migration.verbose = ENV["VERBOSE"] ? ENV["VERBOSE"] == "true" : true
    ActiveRecord::Migrator.migrate(ActiveRecord::Migrator.migrations_paths, ENV["VERSION"] ? ENV["VERSION"].to_i : nil)
  end

  def write_migration(up, down, name, run=false)
    time = Time.now.utc.strftime("%Y%m%d%H%M%S")
    
    dir = File.join(Rails.root, "db", "migrate", "*#{name}*.rb")
    lp = `ls -1 #{dir} 2> /dev/null`.split("\n").length + 1

    fname = File.join(Rails.root, "db", "migrate", "#{time}_#{name}_#{lp}.rb")
    
    File.open(fname, "w"){|f| f.write(migration_template(name, up, down).sub(name.classify, name.classify+lp.to_s)) }

    ar_migrate! if run
  end
end

