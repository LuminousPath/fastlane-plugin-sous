module Fastlane
  module Actions
    module SharedValues
      SIGNED_APK_PATH = :SIGNED_APK_PATH
    end

    class PlateAction < Action
      def self.run(params)
        apk_path = params[:apk_path]
        keystore_path = params[:keystore_path]
        key_password = params[:key_password]
        alias_name = params[:alias_name]
        alias_password = params[:alias_password]
        zip_align = params[:zip_align]

        UI.message "Signing APK #{apk_path}..."
        apk_path = self.sign_apk(
          apk_path: apk_path,
          keystore_path: keystore_path,
          key_password: key_password,
          alias_name: alias_name,
          alias_password: alias_password,
          zip_align: zip_align)

        Actions.lane_context[SharedValues::KEYSTORE_PATH] = apk_path

        apk_path
      end

      def self.sign_apk(apk_path:, keystore_path:, key_password:, alias_name:, alias_password:, zip_align:)

        build_tools_path = self.get_build_tools()

        # https://developer.android.com/studio/command-line/zipalign
        if zip_align == true
          apk_path_aligned = apk_path.gsub(".apk", "-aligned.apk")
          if File.exist?(apk_path_aligned)
            File.delete(apk_path_aligned)
          end
          sh("#{build_tools_path}zipalign 4 \"#{apk_path}\" \"#{apk_path_aligned}\"")
        else
          apk_path_aligned = apk_path
        end
        apk_path_signed = apk_path.gsub(".apk", "-signed.apk")
        apk_path_signed = apk_path_signed.gsub("unsigned", "")
        apk_path_signed = apk_path_signed.gsub("--", "-")

        # https://developer.android.com/studio/command-line/apksigner
        if File.exist?(apk_path_signed)
          File.delete(apk_path_signed)
        end
        sh("#{build_tools_path}apksigner sign --ks \"#{keystore_path}\" --ks-pass pass:\"#{key_password}\" --v1-signing-enabled true --v2-signing-enabled true --out \"#{apk_path_signed}\" \"#{apk_path_aligned}\"")
        
        sh("#{build_tools_path}apksigner verify \"#{apk_path_signed}\"")
        if File.exist?(apk_path_aligned)
          File.delete(apk_path_aligned)
        end

        apk_path_signed
      end

      def self.get_build_tools
        android_home = Helper::SousHelper.get_android_home
        build_tools_root = File.join(android_home, '/build-tools')

        sub_dirs = Dir.glob(File.join(build_tools_root, '*', ''))
        build_tools_last_version = ''
        for sub_dir in sub_dirs
          build_tools_last_version = sub_dir
        end

        build_tools_last_version
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :apk_path,
                                       env_name: "SOUS_APK_PATH",
                                       description: "Path to the APK File",
                                       is_string: true,
                                       verify_block: proc do |value|
                                          UI.user_error!("No APK Path given, pass using `apk_path: 'path to apk'`") unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :keystore_path,
                                       env_name: "SOUS_KEYSTORE_PATH",
                                       description: "Path to the Keystore file to sign APKs",
                                       is_string: true,
                                       verify_block: proc do |value|
                                          UI.user_error!("Keystore path is not present, pass using `keystore_path: 'path to keystore'`") unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :key_password,
                                       env_name: "SOUS_KEY_PASSWORD",
                                       description: "Signing Keystore password",
                                       is_string: true,
                                       verify_block: proc do |value|
                                          UI.user_error!("No Keystore password given, pass using `key_password: 'password'`") unless (value and not value.empty?)
                                       end),
          FastlaneCore::ConfigItem.new(key: :alias_name,
                                       env_name: "SOUS_ALIAS_NAME",
                                       description: "Keystore Alias name",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :alias_password,
                                       env_name: "SOUS_ALIAS_PASSWORD",
                                       description: "URL to the git repo containing the android secrets",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :zip_align,
                                       env_name: "SOUS_ZIP_ALIGN",
                                       description: "Whether to specifically zip align the apk before signing",
                                       is_string: false,
                                       optional: true,
                                       default_value: false)
        ]
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "This action signs apks using an existing keystore"
      end

      def self.details
        "You can use this action to sign APKs"
      end

      def self.output
        [
          ['SIGNED_APK_PATH', 'The path to the signed apk file']
        ]
      end

      def self.authors
        ["Jonathan Nogueira"]
      end

      def self.is_supported?(platform)
        platform == :android
      end
    end
  end
end