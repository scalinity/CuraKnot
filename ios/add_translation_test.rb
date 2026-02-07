require 'xcodeproj'
require 'pathname'

project = Xcodeproj::Project.open('CuraKnot.xcodeproj')
test_target = project.targets.find { |t| t.name == 'CuraKnotTests' }

unless test_target
  puts "ERROR: Could not find CuraKnotTests target"
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

file_path = "CuraKnotTests/Features/TranslationServiceTests.swift"
group, filename = find_or_create_group(project, file_path)

existing = group.children.find { |c|
  c.is_a?(Xcodeproj::Project::Object::PBXFileReference) && c.path == filename
}
if existing
  puts "Already exists: #{file_path}"
else
  file_ref = group.new_reference(filename)
  file_ref.source_tree = '<group>'
  file_ref.last_known_file_type = 'sourcecode.swift'
  test_target.source_build_phase.add_file_reference(file_ref)
  puts "Added: #{file_path}"
end

project.save
puts "Project saved"
