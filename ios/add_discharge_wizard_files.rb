#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project_path = 'CuraKnot.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'CuraKnot' }

unless app_target
  puts "Error: Could not find CuraKnot target"
  exit 1
end

# Helper to find/create group hierarchy matching filesystem
def find_or_create_group(project, file_path)
  components = Pathname.new(file_path).each_filename.to_a
  filename = components.pop

  current_group = project.main_group
  components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && (c.name == component || c.path == component)
    }
    current_group = child || current_group.new_group(component, component)
  end

  [current_group, filename]
end

# Files to add
files_to_add = [
  # Database Models
  "CuraKnot/Core/Database/Models/DischargeRecord.swift",
  "CuraKnot/Core/Database/Models/DischargeTemplate.swift",
  "CuraKnot/Core/Database/Models/DischargeChecklistItem.swift",

  # Feature files
  "CuraKnot/Features/DischargeWizard/DischargeWizardService.swift",
  "CuraKnot/Features/DischargeWizard/DischargeWizardViewModel.swift",
  "CuraKnot/Features/DischargeWizard/DischargeWizardView.swift",
  "CuraKnot/Features/DischargeWizard/WizardStepViews.swift",
]

added_count = 0
skipped_count = 0

files_to_add.each do |file_path|
  full_path = File.join(Dir.pwd, file_path)

  unless File.exist?(full_path)
    puts "Warning: File not found: #{file_path}"
    next
  end

  group, filename = find_or_create_group(project, file_path)

  # Check if file already exists in group
  existing = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXFileReference) && c.path == filename }

  if existing
    puts "Skipped (already exists): #{file_path}"
    skipped_count += 1
    next
  end

  # Add file reference
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'

  # Add to target's source build phase
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
  added_count += 1
end

project.save
puts "\nDone! Added #{added_count} files, skipped #{skipped_count} existing files."
