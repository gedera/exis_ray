#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'json'
require 'net/http'
require 'uri'

module SkillsSync
  SKILLS_YML = 'skills.yml'
  SKILLS_LOCK = 'skills.lock'
  SKILLS_DIR = File.join('.agents', 'skills')

  GLOBAL_SKILL_PATHS = [
    File.join(Dir.home, '.agents', 'skills'),
    File.join(Dir.home, '.claude', '.agents', 'skills'),
    File.join(Dir.home, '.claude', 'skills')
  ].freeze

  class << self
    def run
      config_path = File.join(Dir.pwd, SKILLS_YML)

      unless File.exist?(config_path)
        puts "skill-manager sync — ERROR: #{SKILLS_YML} no encontrado en #{Dir.pwd}"
        exit 1
      end

      config = YAML.safe_load_file(config_path)
      @local_skills_path = File.join(Dir.pwd, SKILLS_DIR)
      FileUtils.mkdir_p(@local_skills_path)

      @use_gh = !gh_available?.nil?
      @token = ENV['GITHUB_TOKEN']

      unless @use_gh || @token
        puts "skill-manager sync — WARNING: ni 'gh' CLI ni GITHUB_TOKEN disponibles. Solo se sincronizarán gemas locales."
      end

      @previous_lock = load_lock
      @current_lock = []

      sync_gems(config['gems'] || [])
      sync_services(config['services'] || [])
      sync_skills(config['skills'] || [])

      cleanup_removed_skills
      save_lock

      puts 'skill-manager sync — OK.'
    end

    private

    # --- Lock file ---

    def load_lock
      lock_path = File.join(Dir.pwd, SKILLS_LOCK)
      return [] unless File.exist?(lock_path)

      data = YAML.safe_load_file(lock_path)
      data['skills'] || []
    rescue StandardError
      []
    end

    def save_lock
      lock_path = File.join(Dir.pwd, SKILLS_LOCK)
      data = {
        'synced_at' => Time.now.strftime('%Y-%m-%d %H:%M:%S'),
        'skills' => @current_lock.sort_by { |s| s['name'] }
      }
      File.write(lock_path, YAML.dump(data))
    end

    def record_lock(name, scope, path)
      @current_lock << { 'name' => name, 'scope' => scope || 'local', 'path' => path }
    end

    def cleanup_removed_skills
      previous_names = @previous_lock.map { |s| s['name'] }
      current_names = @current_lock.map { |s| s['name'] }
      removed = previous_names - current_names

      removed.each do |name|
        entry = @previous_lock.find { |s| s['name'] == name }
        path = entry['path']

        if File.exist?(path)
          puts "  #{name} — eliminado (ya no está en #{SKILLS_YML})"
          FileUtils.rm_rf(path)
        end
      end
    end

    # --- Scope resolution ---

    def resolve_dest(name, scope)
      case scope
      when 'global'
        global_path = find_global_path(name) || default_global_path
        dest = File.join(global_path, name)
        local_path = File.join(@local_skills_path, name)

        # Si existe local, borrarla
        if File.exist?(local_path)
          puts "  #{name} — eliminando copia local (scope: global)"
          FileUtils.rm_rf(local_path)
        end

        dest
      else # local o sin especificar
        # Si existe global, saltear
        existing_global = find_global_path(name)
        if existing_global
          puts "  #{name} — disponible globalmente en #{File.join(existing_global, name)}. Saltando."
          return nil
        end

        File.join(@local_skills_path, name)
      end
    end

    def find_global_path(name)
      GLOBAL_SKILL_PATHS.find do |path|
        File.exist?(File.join(path, name, 'SKILL.md'))
      end
    end

    def default_global_path
      existing = GLOBAL_SKILL_PATHS.find { |p| File.directory?(p) }
      return existing if existing

      path = GLOBAL_SKILL_PATHS.first
      FileUtils.mkdir_p(path)
      path
    end

    # --- Sync methods ---

    def sync_gems(gems)
      gems.each do |gem_config|
        name = gem_config['name']
        scope = gem_config['scope']
        dest = resolve_dest(name, scope)
        next unless dest

        begin
          spec = Gem::Specification.find_by_name(name)
        rescue Gem::MissingSpecError
          puts "  WARNING: gema '#{name}' no instalada. Saltando."
          next
        end

        skill_dir = File.join(spec.gem_dir, 'skill')
        skill_file = File.join(skill_dir, 'SKILL.md')

        unless File.exist?(skill_file)
          puts "  WARNING: #{name} v#{spec.version} no incluye skill en skill/. Saltando."
          next
        end

        scope_label = scope == 'global' ? 'global' : 'local'
        puts "  #{name} v#{spec.version} (#{scope_label})"
        replace_dir(dest)
        FileUtils.cp_r(Dir[File.join(skill_dir, '*')], dest)
        record_lock(name, scope, dest)
      end
    end

    def sync_services(services)
      services.each do |service|
        name = service['name']
        scope = service['scope']
        dest = resolve_dest(name, scope)
        next unless dest

        repo = service['repo']
        scope_label = scope == 'global' ? 'global' : 'local'
        puts "  #{name} (GitHub: #{repo}, skill/) [#{scope_label}]"
        replace_dir(dest)
        download_github_dir(repo, 'main', 'skill', dest)
        record_lock(name, scope, dest)
      end
    end

    def sync_skills(skills)
      skills.each do |skill|
        name = skill['name']
        scope = skill['scope']
        dest = resolve_dest(name, scope)
        next unless dest

        repo = skill['repo']
        remote_path = skill['path'] || "#{SKILLS_DIR}/#{name}"
        scope_label = scope == 'global' ? 'global' : 'local'
        puts "  #{name} (GitHub: #{repo}, #{remote_path}/) [#{scope_label}]"
        replace_dir(dest)
        download_github_dir(repo, 'main', remote_path, dest)
        record_lock(name, scope, dest)
      end
    end

    # --- Helpers ---

    def replace_dir(dest)
      FileUtils.rm_rf(dest)
      FileUtils.mkdir_p(dest)
    end

    def download_github_dir(repo, ref, remote_path, dest)
      entries = list_github_dir(repo, ref, remote_path)

      if entries.empty?
        puts "  WARNING: #{remote_path}/ no encontrado en #{repo}@#{ref}. Saltando."
        return
      end

      entries.each do |entry|
        next unless entry['type'] == 'file'

        relative_path = entry['path'].sub(%r{^#{Regexp.escape(remote_path)}/}, '')
        file_dest = File.join(dest, relative_path)
        FileUtils.mkdir_p(File.dirname(file_dest))

        content = if @use_gh
                    gh_fetch_file(repo, ref, entry['path'])
                  else
                    fetch_url(entry['download_url'])
                  end

        if content
          File.write(file_dest, content)
        else
          puts "  WARNING: no se pudo descargar #{entry['path']} de #{repo}."
        end
      end
    end

    def list_github_dir(repo, ref, path)
      response = if @use_gh
                   gh_api("repos/#{repo}/contents/#{path}?ref=#{ref}")
                 else
                   fetch_url("https://api.github.com/repos/#{repo}/contents/#{path}?ref=#{ref}")
                 end
      return [] unless response

      items = JSON.parse(response)
      return [] unless items.is_a?(Array)

      all_entries = []
      items.each do |item|
        if item['type'] == 'dir'
          all_entries.concat(list_github_dir(repo, ref, item['path']))
        else
          all_entries << item
        end
      end
      all_entries
    end

    # --- GitHub CLI ---

    def gh_available?
      `which gh 2>/dev/null`.strip
      $?.success? ? true : nil
    rescue StandardError
      nil
    end

    def gh_api(endpoint)
      output = `gh api "#{endpoint}" 2>/dev/null`
      $?.success? ? output.force_encoding('UTF-8') : nil
    rescue StandardError
      nil
    end

    def gh_fetch_file(repo, ref, path)
      output = `gh api "repos/#{repo}/contents/#{path}?ref=#{ref}" --jq '.content' 2>/dev/null`
      return nil unless $?.success?

      require 'base64'
      Base64.decode64(output).force_encoding('UTF-8')
    rescue StandardError
      nil
    end

    # --- HTTP directo ---

    def fetch_url(url)
      uri = URI.parse(url)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = "Bearer #{@token}" if @token
      request['User-Agent'] = 'skill-manager/1.0'
      request['Accept'] = 'application/vnd.github.v3+json' if url.include?('api.github.com')

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      response.code == '200' ? response.body.force_encoding('UTF-8') : nil
    rescue StandardError => e
      puts "  ERROR fetching #{url}: #{e.message}"
      nil
    end
  end
end

SkillsSync.run if __FILE__ == $PROGRAM_NAME
