#!/usr/bin/env ruby
require 'xcodeproj'
require 'fileutils'

# Open the project
project_path = 'CuraKnot.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main app target
main_target = project.targets.find { |t| t.name == 'CuraKnot' }

puts "Adding Watch targets to #{project_path}..."

# ============================================================================
# Create CuraKnotWatch Target (watchOS App)
# ============================================================================

watch_target = project.new_target(:watch2_app, 'CuraKnotWatch', :watchos, '10.0')
watch_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.curaknot.app.watchos'
  config.build_settings['INFOPLIST_FILE'] = 'CuraKnotWatch/Info.plist'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = ''
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '4'  # Watch
  config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '10.0'
end

puts "  Created CuraKnotWatch target"

# ============================================================================
# Create CuraKnotWatchWidget Target (Widget Extension)
# ============================================================================

widget_target = project.new_target(:watch2_extension, 'CuraKnotWatchWidget', :watchos, '10.0')
widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.curaknot.app.watchos.widgets'
  config.build_settings['INFOPLIST_FILE'] = 'CuraKnotWatchWidget/Info.plist'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = ''
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '4'  # Watch
  config.build_settings['WATCHOS_DEPLOYMENT_TARGET'] = '10.0'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
end

puts "  Created CuraKnotWatchWidget target"

# ============================================================================
# Create Groups and Add Files
# ============================================================================

def find_or_create_group(project, path_components, parent = nil)
  current_group = parent || project.main_group

  path_components.each do |component|
    child = current_group.children.find { |c|
      c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.name == component
    }

    if child
      current_group = child
    else
      current_group = current_group.new_group(component, component)
    end
  end

  current_group
end

def add_swift_file(project, target, group, file_path)
  return unless File.exist?(file_path)

  filename = File.basename(file_path)

  # Check if file already exists in group
  existing = group.children.find { |c| c.name == filename }
  return existing if existing

  file_ref = group.new_reference(filename)
  file_ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(file_ref)

  puts "    Added: #{file_path}"
  file_ref
end

# Add Shared files to both iOS and Watch targets
shared_group = find_or_create_group(project, ['Shared'])
shared_files = Dir.glob('Shared/*.swift')
shared_files.each do |file|
  add_swift_file(project, main_target, shared_group, file)
  # Also add to Watch target - we'll reference the same file
end

# Add WatchConnectivity files to iOS target
watch_conn_group = find_or_create_group(project, ['CuraKnot', 'Core', 'WatchConnectivity'])
watch_conn_files = Dir.glob('CuraKnot/Core/WatchConnectivity/*.swift')
watch_conn_files.each do |file|
  add_swift_file(project, main_target, watch_conn_group, file)
end

# Add CuraKnotWatch files
watch_group = find_or_create_group(project, ['CuraKnotWatch'])
watch_views_group = find_or_create_group(project, ['CuraKnotWatch', 'Views'])
watch_viewmodels_group = find_or_create_group(project, ['CuraKnotWatch', 'ViewModels'])
watch_services_group = find_or_create_group(project, ['CuraKnotWatch', 'Services'])
watch_models_group = find_or_create_group(project, ['CuraKnotWatch', 'Models'])

# Add Watch app entry point
add_swift_file(project, watch_target, watch_group, 'CuraKnotWatch/CuraKnotWatchApp.swift')

# Add Watch views
Dir.glob('CuraKnotWatch/Views/*.swift').each do |file|
  add_swift_file(project, watch_target, watch_views_group, file)
end

# Add Watch services
Dir.glob('CuraKnotWatch/Services/*.swift').each do |file|
  add_swift_file(project, watch_target, watch_services_group, file)
end

# Add Watch models
Dir.glob('CuraKnotWatch/Models/*.swift').each do |file|
  add_swift_file(project, watch_target, watch_models_group, file)
end

# Add shared models to Watch target
shared_files.each do |file|
  filename = File.basename(file)
  existing = shared_group.children.find { |c| c.name == filename }
  if existing
    watch_target.source_build_phase.add_file_reference(existing)
    puts "    Added to Watch: #{file}"
  end
end

# Add CuraKnotWatchWidget files
widget_group = find_or_create_group(project, ['CuraKnotWatchWidget'])

Dir.glob('CuraKnotWatchWidget/*.swift').each do |file|
  add_swift_file(project, widget_target, widget_group, file)
end

# Add shared models to Widget target
shared_files.each do |file|
  filename = File.basename(file)
  existing = shared_group.children.find { |c| c.name == filename }
  if existing
    widget_target.source_build_phase.add_file_reference(existing)
    puts "    Added to Widget: #{file}"
  end
end

# ============================================================================
# Create Info.plist Files
# ============================================================================

watch_info_plist = <<-PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>CuraKnot</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
    </array>
    <key>WKApplication</key>
    <true/>
    <key>WKWatchOnly</key>
    <false/>
    <key>NSMicrophoneUsageDescription</key>
    <string>CuraKnot needs microphone access to record voice handoffs</string>
</dict>
</plist>
PLIST

widget_info_plist = <<-PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>$(DEVELOPMENT_LANGUAGE)</string>
    <key>CFBundleDisplayName</key>
    <string>CuraKnot Widgets</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
    </dict>
</dict>
</plist>
PLIST

# Write Info.plist files
FileUtils.mkdir_p('CuraKnotWatch')
File.write('CuraKnotWatch/Info.plist', watch_info_plist)
puts "  Created CuraKnotWatch/Info.plist"

FileUtils.mkdir_p('CuraKnotWatchWidget')
File.write('CuraKnotWatchWidget/Info.plist', widget_info_plist)
puts "  Created CuraKnotWatchWidget/Info.plist"

# ============================================================================
# Set Target Dependencies
# ============================================================================

# Widget depends on Watch app
watch_target.add_dependency(widget_target)

# Main app embeds Watch app
# Create embed frameworks build phase for Watch app
main_target.build_configurations.each do |config|
  # Add WatchConnectivity framework
  config.build_settings['OTHER_LDFLAGS'] ||= ['$(inherited)']
end

puts "  Set up target dependencies"

# ============================================================================
# Save Project
# ============================================================================

project.save
puts "\nProject saved successfully!"
puts "\nNext steps:"
puts "1. Open CuraKnot.xcodeproj in Xcode"
puts "2. Select the CuraKnotWatch target"
puts "3. Set your development team in Signing & Capabilities"
puts "4. Add the 'App Groups' capability with group: group.com.curaknot.app"
puts "5. Build and run on Apple Watch simulator"
