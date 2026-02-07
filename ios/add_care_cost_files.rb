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

puts "Adding CareCost feature files to Xcode project..."
puts

app_files = [
  # Database models
  "CuraKnot/Core/Database/Models/CareExpense.swift",
  "CuraKnot/Core/Database/Models/CareCostEstimate.swift",
  "CuraKnot/Core/Database/Models/LocalCareCost.swift",
  "CuraKnot/Core/Database/Models/FinancialResource.swift",

  # Service
  "CuraKnot/Features/CareCost/CareCostService.swift",

  # ViewModels
  "CuraKnot/Features/CareCost/CareCostDashboardViewModel.swift",
  "CuraKnot/Features/CareCost/ExpenseTrackerViewModel.swift",
  "CuraKnot/Features/CareCost/AddExpenseViewModel.swift",
  "CuraKnot/Features/CareCost/CostProjectionsViewModel.swift",
  "CuraKnot/Features/CareCost/FinancialResourcesViewModel.swift",

  # Views
  "CuraKnot/Features/CareCost/CareCostDashboardView.swift",
  "CuraKnot/Features/CareCost/ExpenseTrackerView.swift",
  "CuraKnot/Features/CareCost/AddExpenseSheet.swift",
  "CuraKnot/Features/CareCost/CostProjectionsView.swift",
  "CuraKnot/Features/CareCost/FinancialResourcesView.swift",

  # Components
  "CuraKnot/Features/CareCost/Components/MonthlyCostCard.swift",
  "CuraKnot/Features/CareCost/Components/CoverageStatusCard.swift",
  "CuraKnot/Features/CareCost/Components/ScenarioCard.swift",
  "CuraKnot/Features/CareCost/Components/ExpenseRow.swift",
  "CuraKnot/Features/CareCost/Components/ResourceCard.swift",
  "CuraKnot/Features/CareCost/Components/FinancialDisclaimerView.swift",
]

app_files.each do |f|
  add_file(project, app_target, f)
end

puts
puts "Adding test files..."
test_files = [
  "CuraKnotTests/Features/CareCostServiceTests.swift",
  "CuraKnotTests/Features/CareCostViewModelTests.swift",
]

test_files.each do |f|
  add_file(project, test_target, f)
end

project.save
puts
puts "Done! #{app_files.length} app files + #{test_files.length} test files processed."
