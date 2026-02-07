#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project = Xcodeproj::Project.open('CuraKnot.xcodeproj')
app_target = project.targets.find { |t| t.name == 'CuraKnot' }

unless app_target
  puts "ERROR: Could not find CuraKnot target"
  exit 1
end

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

files = [
  # Features/Translation (10 files)
  "CuraKnot/Features/Translation/SupportedLanguage.swift",
  "CuraKnot/Features/Translation/TranslationMode.swift",
  "CuraKnot/Features/Translation/TranslatedContent.swift",
  "CuraKnot/Features/Translation/TranslationService.swift",
  "CuraKnot/Features/Translation/LanguageSettingsView.swift",
  "CuraKnot/Features/Translation/TranslatedHandoffView.swift",
  "CuraKnot/Features/Translation/MedicalTranslationDisclaimer.swift",
  "CuraKnot/Features/Translation/GlossaryEditorView.swift",
  "CuraKnot/Features/Translation/AddGlossaryTermSheet.swift",
  "CuraKnot/Features/Translation/CircleLanguageOverviewView.swift",
  # Core/Database/Models (3 files)
  "CuraKnot/Core/Database/Models/HandoffTranslation.swift",
  "CuraKnot/Core/Database/Models/TranslationGlossaryEntry.swift",
  "CuraKnot/Core/Database/Models/TranslationCacheEntry.swift",
]

added_count = 0
skipped_count = 0

files.each do |file_path|
  group, filename = find_or_create_group(project, file_path)

  # Check if file already exists in group
  existing = group.children.find { |c|
    c.is_a?(Xcodeproj::Project::Object::PBXFileReference) && c.path == filename
  }
  if existing
    puts "Already exists: #{file_path}"
    skipped_count += 1
    next
  end

  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_path}"
  added_count += 1
end

project.save
puts ""
puts "Project saved successfully"
puts "Added: #{added_count} files, Skipped: #{skipped_count} files"
