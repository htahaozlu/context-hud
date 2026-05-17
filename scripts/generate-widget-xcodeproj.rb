#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "xcodeproj"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "packaging", "macos", "ContextBarWidget.xcodeproj")

FileUtils.rm_rf(project_path)

project = Xcodeproj::Project.new(project_path)

sources_group = project.main_group.new_group("Sources")
config_group = project.main_group.new_group("Configuration")
frameworks_group = project.frameworks_group

widget_source = sources_group.new_file("../../menubar/widget/Widget.swift")
info_plist = config_group.new_file("widget/Info.plist")
entitlements = config_group.new_file("widget/Widget.entitlements")

target = project.new_target(:app_extension, "ContextBarWidget", :osx, "13.0")
target.source_build_phase.add_file_reference(widget_source)

%w[WidgetKit SwiftUI AppKit].each do |framework|
  ref = frameworks_group.new_file("System/Library/Frameworks/#{framework}.framework")
  ref.source_tree = "SDKROOT"
  target.frameworks_build_phase.add_file_reference(ref)
end

target.build_configurations.each do |config|
  config.build_settings.merge!(
    "APPLICATION_EXTENSION_API_ONLY" => "YES",
    "CODE_SIGN_ENTITLEMENTS" => "$(SRCROOT)/widget/Widget.entitlements",
    "CODE_SIGN_STYLE" => "Manual",
    "COMBINE_HIDPI_IMAGES" => "YES",
    "CURRENT_PROJECT_VERSION" => "1",
    "DEVELOPMENT_TEAM" => "",
    "GENERATE_INFOPLIST_FILE" => "NO",
    "INFOPLIST_FILE" => "$(SRCROOT)/widget/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS" => [
      "$(inherited)",
      "@executable_path/../Frameworks",
      "@executable_path/../../../../Frameworks"
    ],
    "MACOSX_DEPLOYMENT_TARGET" => "13.0",
    "MARKETING_VERSION" => "0.1.0",
    "ONLY_ACTIVE_ARCH" => "NO",
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.htahaozlu.contextbar.widget",
    "PRODUCT_NAME" => "ContextBarWidget",
    "SDKROOT" => "macosx",
    "SKIP_INSTALL" => "YES",
    "SUPPORTED_PLATFORMS" => "macosx",
    "SWIFT_VERSION" => "5.0",
    "WRAPPER_EXTENSION" => "appex"
  )
end

project.save

puts "Generated #{project_path}"
