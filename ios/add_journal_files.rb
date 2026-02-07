#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project_path = 'CuraKnot.xcodeproj'
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == 'CuraKnot' }

# Helper to find or create group hierarchy
def find_or_create_group(parent_group, path_components)
  return parent_group if path_components.empty?

  component = path_components.first
  remaining = path_components[1..-1]

  child = parent_group.children.find { |c|
    c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component
  }

  unless child
    child = parent_group.new_group(component, component)
  end

  find_or_create_group(child, remaining)
end

# Find the CuraKnot main group
main_group = project.main_group.children.find { |c| c.name == 'CuraKnot' }

# Files to add (relative to ios/CuraKnot/)
files_to_add = [
  # Core Database Models
  'Core/Database/Models/JournalEntry.swift',

  # Journal Feature - Models
  'Features/Journal/Models/MilestoneType.swift',
  'Features/Journal/Models/EntryVisibility.swift',
  'Features/Journal/Models/JournalEntryType.swift',
  'Features/Journal/Models/JournalFilter.swift',

  # Journal Feature - Services
  'Features/Journal/Services/JournalPhotoUploader.swift',
  'Features/Journal/Services/JournalService.swift',

  # Journal Feature - ViewModels
  'Features/Journal/ViewModels/JournalListViewModel.swift',
  'Features/Journal/ViewModels/JournalEntryViewModel.swift',
  'Features/Journal/ViewModels/MemoryBookViewModel.swift',

  # Journal Feature - Components
  'Features/Journal/Components/VisibilityToggle.swift',
  'Features/Journal/Components/UsageLimitBanner.swift',
  'Features/Journal/Components/PhotoThumbnailGrid.swift',

  # Journal Feature - Views
  'Features/Journal/Views/JournalEmptyState.swift',
  'Features/Journal/Views/JournalEntryRow.swift',
  'Features/Journal/Views/JournalEntryDetailView.swift',
  'Features/Journal/Views/JournalEntrySheet.swift',
  'Features/Journal/Views/JournalListView.swift',
  'Features/Journal/Views/MemoryBookExportView.swift',
]

files_to_add.each do |file_path|
  # Parse path components
  components = file_path.split('/')
  filename = components.pop

  # Find or create the group hierarchy
  group = find_or_create_group(main_group, components)

  # Check if file already exists in group
  existing = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXFileReference) && c.name == filename }

  if existing
    puts "Skipping (already exists): #{file_path}"
    next
  end

  # Add file reference
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'

  # Add to target's compile sources
  app_target.source_build_phase.add_file_reference(file_ref)

  puts "Added: #{file_path}"
end

project.save
puts "\nProject saved successfully!"
