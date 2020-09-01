require 'fastlane_core/ui/ui'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class SousHelper
      
      def self.get_android_home
        android_home = File.absolute_path(ENV["ANDROID_HOME"])
        android_home
      end
    end
  end
end
