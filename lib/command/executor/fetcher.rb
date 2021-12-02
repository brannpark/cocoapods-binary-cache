require "parallel"
require_relative "base"
require_relative "../helper/zip"

module PodPrebuild
  class CacheFetcher < CommandExecutor
    attr_reader :cache_branch

    def initialize(options)
      super(options)
      @cache_branch = options[:cache_branch]
    end

    def run
      Pod::UI.step("Fetching cache") do
        if @config.local_cache?
          print_message_for_local_cache(@config.cache_path)
        else
          fetch_remote_cache(@config.cache_repo, @cache_branch, @config.cache_path)
        end
        
        unless unzip_cache > 0
          raise "No caches to unzip"
        end
      end
    end

    private

    def print_message_for_local_cache(cache_dir)
      Pod::UI.puts "You're using local cache at: #{cache_dir}.".yellow
      message = <<~HEREDOC
        To enable remote cache (with a git repo), add the `remote` field to the repo config in the `cache_repo` option.
        For more details, check out this doc:
          https://github.com/grab/cocoapods-binary-cache/blob/master/docs/configure_cocoapods_binary_cache.md#cache_repo-
      HEREDOC
      Pod::UI.puts message
    end

    def fetch_remote_cache(repo, branch, dest_dir)
      Pod::UI.puts "Fetching cache from #{repo} (branch: #{branch})".green
      unless Dir.exist?(dest_dir + "/.git")
        FileUtils.rm_rf(dest_dir)
        git_clone("#{repo} #{dest_dir}")
      end
      git("fetch", can_fail: true)
      git("checkout #{branch}", can_fail: true)
      git("checkout -b #{branch} master", can_fail: true)
    end

    def unzip_cache
      Pod::UI.puts "Unzipping cache: #{@config.cache_path} -> #{@config.prebuild_sandbox_path}".green
      FileUtils.rm_rf(@config.prebuild_sandbox_path)
      FileUtils.mkdir_p(@config.prebuild_sandbox_path)

      if File.exist?(@config.manifest_path(in_cache: true))
        FileUtils.cp(
          @config.manifest_path(in_cache: true),
          @config.manifest_path
        )
      end
      zip_paths = Dir[@config.generated_frameworks_dir(in_cache: true) + "/*.zip"]
      Parallel.each(zip_paths, in_threads: 8) do |path|
        ZipUtils.unzip(path, to_dir: @config.generated_frameworks_dir)
      end
      zip_paths.size
    end
  end
end
