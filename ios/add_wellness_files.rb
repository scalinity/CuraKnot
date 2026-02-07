#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'CuraKnot.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'CuraKnot' }

# Find or create group hierarchy
def find_or_create_group(project, path_components)
  current_group = project.main_group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == 'CuraKnot' }
  return nil unless current_group

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

# Files to add (relative to CuraKnot/)
wellness_files = [
  # Models
  ['Features', 'Wellness', 'Models', 'WellnessCheckIn.swift'],
  ['Features', 'Wellness', 'Models', 'WellnessAlert.swift'],
  ['Features', 'Wellness', 'Models', 'WellnessPreferences.swift'],
  # Services
  ['Features', 'Wellness', 'Services', 'EncryptionService.swift'],
  ['Features', 'Wellness', 'Services', 'WellnessService.swift'],
  # ViewModels
  ['Features', 'Wellness', 'ViewModels', 'WellnessViewModel.swift'],
  ['Features', 'Wellness', 'ViewModels', 'CheckInViewModel.swift'],
  ['Features', 'Wellness', 'ViewModels', 'WellnessDashboardViewModel.swift'],
  # Views
  ['Features', 'Wellness', 'Views', 'WellnessView.swift'],
  ['Features', 'Wellness', 'Views', 'WellnessTabView.swift'],
  ['Features', 'Wellness', 'Views', 'WellnessPreviewView.swift'],
  ['Features', 'Wellness', 'Views', 'CheckInView.swift'],
  ['Features', 'Wellness', 'Views', 'WellnessDashboardView.swift'],
  ['Features', 'Wellness', 'Views', 'WellnessSettingsView.swift'],
  # Components
  ['Features', 'Wellness', 'Views', 'Components', 'AlertBannerView.swift'],
  ['Features', 'Wellness', 'Views', 'Components', 'WellnessScoreCard.swift'],
]

wellness_files.each do |components|
  filename = components.pop
  group = find_or_create_group(project, components)

  if group.nil?
    puts "ERROR: Could not find or create group for #{components.join('/')}"
    next
  end

  # Check if file already exists in group
  existing = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXFileReference) && c.name == filename }
  if existing
    puts "SKIP: #{components.join('/')}/#{filename} (already exists)"
    next
  end

  # Add file reference
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'

  # Add to target
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "ADDED: #{components.join('/')}/#{filename}"
end

project.save
puts "\nProject saved successfully!"
