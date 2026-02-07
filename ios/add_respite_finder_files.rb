#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project = Xcodeproj::Project.open('CuraKnot.xcodeproj')
app_target = project.targets.find { |t| t.name == 'CuraKnot' }
test_target = project.targets.find { |t| t.name == 'CuraKnotTests' }

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

def add_file(project, target, file_path)
  group, filename = find_or_create_group(project, file_path)

  # Check if file already exists in group
  existing = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXFileReference) && c.path == filename }
  if existing
    puts "  SKIP (exists): #{file_path}"
    return
  end

  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)
  puts "  ADDED: #{file_path}"
end

puts "Adding Respite Finder files to CuraKnot project..."
puts ""

# App target files
app_files = [
  "CuraKnot/Features/RespiteFinder/RespiteModels.swift",
  "CuraKnot/Features/RespiteFinder/RespiteFinderService.swift",
  "CuraKnot/Features/RespiteFinder/RespiteFinderViewModel.swift",
  "CuraKnot/Features/RespiteFinder/RespiteRequestViewModel.swift",
  "CuraKnot/Features/RespiteFinder/RespiteFinderTabView.swift",
  "CuraKnot/Features/RespiteFinder/Views/RespiteFinderView.swift",
  "CuraKnot/Features/RespiteFinder/Views/ProviderCard.swift",
  "CuraKnot/Features/RespiteFinder/Views/RatingStars.swift",
  "CuraKnot/Features/RespiteFinder/Views/ProviderDetailView.swift",
  "CuraKnot/Features/RespiteFinder/Views/RespiteRequestSheet.swift",
  "CuraKnot/Features/RespiteFinder/Views/RespiteHistoryView.swift",
]

puts "App target files:"
app_files.each { |f| add_file(project, app_target, f) }

puts ""

# Test target files
test_files = [
  "CuraKnotTests/Features/RespiteFinderTests.swift",
]

puts "Test target files:"
test_files.each { |f| add_file(project, test_target, f) }

project.save
puts ""
puts "Done! #{app_files.length} app files + #{test_files.length} test files added."
