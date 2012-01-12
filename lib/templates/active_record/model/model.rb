<% module_namespacing do -%>
# encoding: utf-8
class <%= class_name %> < <%= parent_class_name.classify %>
<% attributes.select {|attr| attr.reference? }.each do |attribute| -%>
  belongs_to :<%= attribute.name %>
<% end -%>

  column :id, :integer
<% attributes.reject {|attr| attr.reference? }.each do |attr| -%>
  column :<%= attr.name %>, :<%= attr.type %>
<% end -%>
<% {
  "Validations" => "Declarations of model required structure.",
  "Named Scopes" => "Scopes and methods for narrowing down SQL Queries", 
  "Class Methods" => "Class methods not related to finding records.", 
  "Initialization" => "Declarations of initialization commands (creation procedures/constructors)", 
  "Access" => "Declarations of non-boolean queries on the object state, e.g. item",
  "Status report" => "Declarations of boolean queries on the object state, e.g. is_empty?",
  "Element change" => "eclarations of commands that change the structure, e.g. update_count!"
}.each do |name, description| %>
<%= "  #### %-14s - %-75s ####" % [name, description] %>
<% end %>
end
<% end -%>
