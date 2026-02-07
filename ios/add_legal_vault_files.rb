#!/usr/bin/env ruby
require 'xcodeproj'
require 'pathname'

project = Xcodeproj::Project.open('CuraKnot.xcodeproj')
app_target = project.targets.find { |t| t.name == 'CuraKnot' }

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

files_to_add = [
  "CuraKnot/Core/Database/Models/LegalDocument.swift",
  "CuraKnot/Features/LegalVault/LegalVaultService.swift",
  "CuraKnot/Features/LegalVault/LegalVaultViewModel.swift",
  "CuraKnot/Features/LegalVault/LegalVaultView.swift",
  "CuraKnot/Features/LegalVault/LegalDocumentRow.swift",
  "CuraKnot/Features/LegalVault/LegalDocumentDetailView.swift",
  "CuraKnot/Features/LegalVault/AddLegalDocumentView.swift",
  "CuraKnot/Features/LegalVault/ShareDocumentSheet.swift",
  "CuraKnot/Features/LegalVault/AccessControlView.swift",
  "CuraKnot/Features/LegalVault/AuditLogView.swift",
  "CuraKnot/Features/LegalVault/EmergencyAccessSettingsView.swift",
]

files_to_add.each do |file_path|
  # Check if file is already in the project
  existing = project.files.find { |f| f.real_path.to_s.end_with?(file_path) }
  if existing
    puts "Already exists: #{file_path}"
    next
  end

  group, filename = find_or_create_group(project, file_path)

  # Check if file ref already exists in this group
  existing_ref = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXFileReference) && c.path == filename }
  if existing_ref
    puts "Reference exists: #{file_path}"
    next
  end

  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  app_target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_path}"
end

project.save
puts "Done! Project saved."
