require 'xcodeproj'
project_path = 'MyStat.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Add files to the project and target
files = [
  'Sources/Monitor/Providers/GPUProvider.swift',
  'Sources/Monitor/Providers/BatteryProvider.swift',
  'Sources/Monitor/Providers/SensorProvider.swift',
  'Sources/UI/BatteryPopoverView.swift'
]

files.each do |file_path|
  # Skip if already in the target
  next if target.source_build_phase.files.any? { |f| f.file_ref && f.file_ref.path == file_path }
  
  # Find or create file reference
  group_path = File.dirname(file_path)
  group = project.main_group
  group_path.split('/').each do |component|
    group = group.groups.find { |g| g.name == component || g.path == component } || group.new_group(component)
  end
  
  file_name = File.basename(file_path)
  file_ref = group.files.find { |f| f.name == file_name || f.path == file_name } || group.new_file(file_name)
  target.add_file_references([file_ref])
end

project.save
puts "Files added to project."
