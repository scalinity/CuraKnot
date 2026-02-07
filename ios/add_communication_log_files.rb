#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'CuraKnot.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'CuraKnot' }

def find_or_create_group(project, path_components)
  current_group = project.main_group

  path_components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && (c.name == component || c.path == component)
    }
    if child
      current_group = child
    else
      current_group = current_group.new_group(component, component)
    end
  end

  current_group
end

def add_file_to_project(project, target, relative_path)
  components = relative_path.split('/')
  filename = components.pop

  group = find_or_create_group(project, components)

  # Check if file already exists in group
  existing = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXFileReference) && c.path == filename }
  if existing
    puts "Already exists: #{relative_path}"
    return
  end

  file_ref = group.new_reference(filename)
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{relative_path}"
end

# Communication Log feature files
files = [
  'CuraKnot/Core/Database/Models/CommunicationLog.swift',
  'CuraKnot/Features/CommunicationLog/Services/CommunicationLogService.swift',
  'CuraKnot/Features/CommunicationLog/ViewModels/CommunicationLogViewModel.swift',
  'CuraKnot/Features/CommunicationLog/Views/CommunicationLogListView.swift',
  'CuraKnot/Features/CommunicationLog/Views/CommunicationLogDetailView.swift',
  'CuraKnot/Features/CommunicationLog/Views/NewCommunicationLogView.swift',
]

files.each do |file_path|
  add_file_to_project(project, app_target, file_path)
end

project.save
puts "\nProject saved successfully!"
