
## Based strongly on the work done at https://github.com/christopherney/fastlane-plugin-match_keystore/blob/master/lib/fastlane/plugin/match_keystore/actions/match_keystore_action.rb

require 'digest'
require 'openssl'
require 'git'

module Fastlane
  module Actions
    module SharedValues
      KEYSTORE_PATH = :KEYSTORE_PATH
    end

    class PassAction < Action
      def self.run(params)
        # input params:
        git_url = params[:git_url]
        git_branch = params[:git_branch]
        package_name = params[:package_name]
        match_secret = params[:match_secret]

        # constants:
        keystore_name = package_name + ".jks"
        keystore_encrypt_name = package_name + ".jks.enc"

        # Check Android Home Env:
        android_home = Helper::SousHelper.get_android_home
        if android_home.to_s.strip.empty?
          raise "The Android SDK is not installed or the environment variable ANDROID_HOME is not defined "
        else
          UI.message("Android SDK: #{android_home}")
        end

        # Check OpenSSL:
        self.check_openssl_version

        # Init working local directory:
        dir_name = File.join(File.absolute_path(ENV['HOME']), '.sous')
        unless File.directory?(dir_name)
          UI.message("Creating '.sous' working directory...")
          FileUtils.mkdir_p(dir_name)
        end

        # Init 'security password' for AES encryption:
        key_name = "#{self.to_md5(git_url)}.hex"
        key_path = File.join(dir_name, key_name)
        unless File.file?(key_path)
          security_password = self.prompt(text: "Security password: ", secure_text: true, ci_input: match_secret)
          if security_password.to_s.strip.empty?
            raise "Security password is not defined! Please use 'match_secret' parameter"
          end
          UI.message("Generating security key '#{key_name}'...")
          self.gen_key(key_path, security_password)
        end

        # check if password is well initialized
        tmpkey = self.get_file_content(key_path).strip
        if tmpkey.length == 128
          UI.message("Security key '#{key_name}' initialized")
        else
          raise "The security key '#{key_name}' is malformed, or not initialized!"
        end

        # create repo directory to sync remote keystores
        repo_dir = File.join(dir_name, self.to_md5(git_url))
        unless File.directory?(repo_dir)
          UI.message("Creating Keystore directory...")
          UI.message("Directory: #{repo_dir}")
          FileUtils.mkdir_p(repo_dir)
        end

        # cloning/pulling git remote repo
        git_dir = File.join(repo_dir, '/.git')
        if !File.directory?(git_dir)
          UI.message("Cloning remote Keystores repository...")
          self.git_clone(git_url, git_branch, self.to_md5(git_url), dir_name)
        else
          UI.message("Pulling remote Keystores repository...#{git_branch}")
          self.git_pull(repo_dir, git_branch)
        end

        # create sub-directory for android app
        if package_name.to_s.strip.empty?
          raise "Package name is not defined!"
        end
        keystore_app_dir = File.join(repo_dir, "android")
        keystore_path = File.join(keystore_app_dir, keystore_name)
        keystore_encrypt_path = File.join(keystore_app_dir, keystore_encrypt_name)

        if !File.file?(keystore_encrypt_path)
          raise "Cannot find encrypted keystore at path: #{keystore_encrypt_path}. Please make sure you have run `prep` at least once and that the keystore is uploaded to your store."
        else
          self.decrypt_file(keystore_encrypt_path, keystore_path, key_path)
        end

        Actions.lane_context[SharedValues::KEYSTORE_PATH] = keystore_path

        keystore_path
      end

      def self.git_clone(git_url, git_branch, repo_name, repo_dir)
        Git.clone(git_url, repo_name, path: repo_dir, branch: git_branch)
      end

      def self.git_pull(repo_dir, git_branch)
        g = Git.open(repo_dir)
        g.fetch
        g.checkout("origin/" + git_branch, force: true)
        g.pull("origin", git_branch)
      end

      def self.to_md5(value)
        hash_value = Digest::MD5.hexdigest(value)
        hash_value
      end

      def self.check_openssl_version
        output = `openssl version`
        unless output.start_with?("OpenSSL")
          raise "Please install OpenSSL at least version 1.1.1 https://www.openssl.org/"
        end
        UI.message("OpenSSL v
          ersion: " + output.strip)
      end

      def self.prompt(params)
        if params[:value].to_s.empty?
          return_value = other_action.prompt(text: params[:text], secure_text: params[:secure_text], ci_input: params[:ci_input])
        else
          return_value = params[:value]
        end
        return_value
      end

      def self.get_file_content(file_path)
        data = File.read(file_path)
        data
      end

      def self.decrypt_file(encrypt_file, clear_file, key_path)
        if File.exist?(clear_file)
          File.delete(clear_file)
        end
        # TODO: Change this to use the actual openssl library instead of a shell command
        sh("openssl enc -d -aes-256-cbc -pbkdf2 -in \"#{encrypt_file}\" -out \"#{clear_file}\" -pass file:\"#{key_path}\"")
      end

      def self.gen_key(key_path, password)
        if File.exist?(key_path)
          File.delete(key_path)
        end
        digest = Digest::SHA512.hexdigest(password)
        File.open(key_path, "w") do |f|
          f << digest
        end
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :git_url,
                                       env_name: "SOUS_GIT_URL",
                                       description: "URL to the git repo containing the android secrets",
                                       is_string: true,
                                       verify_block: proc do |value|
                                         UI.user_error!("No Android Secrets Git Url given, pass using `git_url: 'url_location'`") unless value && !value.empty?
                                       end),
          FastlaneCore::ConfigItem.new(key: :git_branch,
                                       env_name: "SOUS_GIT_BRANCH",
                                       description: "Specific git branch to use",
                                       is_string: true,
                                       default_value: "master"),
          FastlaneCore::ConfigItem.new(key: :match_secret,
                                       env_name: "SOUS_MATCH_PASSWORD",
                                       description: "Passphrase used to encrypt secrets",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :package_name,
                                       env_name: "SOUS_PACKAGE_NAME",
                                       description: "The package name of the App",
                                       is_string: true,
                                       verify_block: proc do |value|
                                         UI.user_error!("No Android Package Name given, pass using `package_name: 'package_name'`") unless value && !value.empty?
                                       end),
          FastlaneCore::ConfigItem.new(key: :existing_keystore,
                                       env_name: "SOUS_KEYSTORE",
                                       description: "Path of an existing Keystore",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :keystore_data,
                                       env_name: "SOUS_JSON_PATH",
                                       description: "Required data to import an existing keystore, or create a new one",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :key_password,
                                       env_name: "SOUS_KEY_PASSWORD",
                                       description: "Keystore Password",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :alias_name,
                                       env_name: "SOUS_ALIAS_NAME",
                                       description: "Keystore Alias name",
                                       is_string: true,
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :alias_password,
                                       env_name: "SOUS_ALIAS_PASSWORD",
                                       description: "Keystore Alias password",
                                       is_string: true,
                                       optional: true)
        ]
      end

      #####################################################
      # @!group Documentation
      #####################################################

      def self.description
        "This action retrieves existing keystores for the android build system"
      end

      def self.details
        "You can use this action to pull the upload and signing keystores for android."
      end

      def self.output
        [
          ['KEYSTORE_PATH', 'The path to the synced keystore file']
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
