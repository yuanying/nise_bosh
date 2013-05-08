require "nise_bosh"
require 'logger'
require 'yaml'
require 'spec_helper'

describe NiseBosh do
  before do
    @tmp_dir = File.join(%w[/tmp nise_bosh_spec])
    @options = {
      :repo_dir => File.join(File.expand_path("."), "spec", "assets", "release"),
      :install_dir => File.join(@tmp_dir, "install"),
      :deploy_manifest => File.join(File.expand_path("."), "spec", "assets", "manifest.yml"),
      :working_dir => File.join(@tmp_dir, "working"),
    }
    @log = Logger.new("/dev/null")

    @package = "miku"
    @package_version = "1.1-dev"
    @package_installed_file = File.join( @options[:install_dir], "packages", @package, "dayo")
    @package_installed_file_contents = "miku #{@package_version}\n"
    @src_file_nonglob = ["miku/file"]
    @src_file_glob = ["variant/haku/file", "variant/neru/file"]
    @src_file = @src_file_nonglob + @src_file_glob

    setup_directory(@options[:working_dir])
    setup_directory(@options[:install_dir])

    @nb = NiseBosh::Builder.new(@options, @log)
    @current_ip = current_ip()
  end

  describe "#new" do
    it "should not raise an error when repo_dir exists" do
      expect { NiseBosh::Builder.new(@options, @log) }.to_not raise_error
    end

    it "should raise an error when repo_dir does not exist" do
      @options[:repo_dir] = "/not/exist"
      expect { NiseBosh::Builder.new(@options, @log) }.to raise_error
    end

    it "should raise an error when repo_dir does have no release index" do
      expect do
        NiseBosh::Builder.new(@options.merge({:repo_dir => File.join(File.expand_path("."), "spec", "assets", "release_noindex")}), @log)
      end.to raise_error("No release index found!\nTry `bosh cleate release` in your release repository.")
    end
  end

  describe "#run_packaging" do
    it "should create the install directory and run the packaging script" do
      @nb.run_packaging(@package)
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
    end

    it "should raise an error when packaging script fails" do
      expect { @nb.run_packaging("fail_packaging") }.to raise_error
    end
  end

  describe "#resolve_dependency" do
    it "should resolve linear dependencies" do
      expect(@nb.resolve_dependency(%w{tako kaito})).to eq(%w{miku luca tako kaito})
    end

    it "should resolve part-and-rejoin dependencies" do
      expect(@nb.resolve_dependency(%w{meiko})).to eq(%w{miku luca tako meiko})
    end

    it "should raise an error when detects a cyclic dependency" do
      @nb = NiseBosh::Builder.new(@options.merge({:release_file => File.join(File.expand_path("."), "spec", "assets", "release_cyclic_dependency.yml")}), @log)
      expect { @nb.resolve_dependency(%w{ren}) }.to raise_error
    end
  end

  describe "#install_package" do
    let(:version_file) { File.join(@options[:install_dir], "packages", @package, ".version") }

    it "should install the given package" do
      @nb.install_package(@package)
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
      expect_contents(version_file).to eq("#{@package_version}\n")
    end

    it "should not install the given package when the package is already installed" do
      @nb.install_package(@package)
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
      expect_contents(version_file).to eq("#{@package_version}\n")
      FileUtils.rm_rf(@package_installed_file)
      expect_file_exists(@package_installed_file).to be_false
      @nb.install_package(@package)
      expect_file_exists(@package_installed_file).to be_false
      expect_contents(version_file).to eq("#{@package_version}\n")
    end

    it "should install the given package even if the package is already installed when force_compile option is true" do
      @nb.install_package(@package)
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
      expect_contents(version_file).to eq("#{@package_version}\n")
      FileUtils.rm_rf(@package_installed_file)
      expect_file_exists(@package_installed_file).to be_false
      force_nb = NiseBosh::Builder.new(@options.merge({:force_compile => true}), @log)
      force_nb.install_package(@package)
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
      expect_contents(version_file).to eq("#{@package_version}\n")
    end

    it "should delete the version file before start packaging" do
      @nb.install_package(@package)
      expect_contents(version_file).to eq("#{@package_version}\n")
      expect do
        fail_while_packaging_nb = NiseBosh::Builder.new(@options.merge({:force_compile => true}), @log)
        def fail_while_packaging_nb.run_packaging(name)
          raise Error
        end
        fail_while_packaging_nb.install_package(@package)
      end.to raise_error
      expect_file_exists(version_file).to be_false
    end
  end

  describe "#install_packages" do
    let(:packages) { %w{meiko kaito tako} }
    let(:related_packages) { %w{luca} }

    it "should install all related packages" do
      @nb.install_packages(packages)
      (packages + related_packages).each do |package|
        expect_contents(@options[:install_dir], "packages", package, "dayo").to eq("tenshi\n")
      end
      expect_contents(@package_installed_file).to eq(@package_installed_file_contents)
    end

    it "should install only given packages when given no_dependency" do
      @nb.install_packages(packages, true)
      packages.each do |package|
        expect_contents(@options[:install_dir], "packages", package, "dayo").to eq("tenshi\n")
      end
      related_packages do |package|
        expect_file_exists(@options[:install_dir], "packages", package).to be_false
      end
    end
  end

  describe "#install_job" do
    def check_templates
      expect_contents(@options[:install_dir], "jobs", "angel", "config", "miku.conf")
        .to eq("tenshi\n0\n#{@current_ip}\n")
      expect_contents(@options[:install_dir], "monit", "job", "0000_legna.angel.monitrc")
        .to eq("monit mode manual")
    end

    it "should install packags and generate required files from template files" do
      @nb.install_job("legna")
      expect_contents(@options[:install_dir], "packages", "miku", "dayo").to eq("miku #{@package_version}\n")
      expect_contents(@options[:install_dir], "packages", "luca", "dayo").to eq("tenshi\n")
      check_templates
      expect_directory_exists(@options[:install_dir], "data", "packages").to be_true
    end

    it "should not install packags and only generate required files from template files when template_only given" do
      @nb.install_job("legna", true)
      expect_file_exists(@options[:install_dir], "packages", "miku", "dayo").to be_false
      expect_file_exists(@options[:install_dir], "packages", "luca", "dayo").to be_false
      check_templates
    end

    it "should fill templates with given IP address and index number, and save file" do
      @nb = NiseBosh::Builder.new(@options.merge({:ip_address => "39.39.39.39", :index => 39}), @log)
      @nb.install_job("legna")
      expect_contents(@options[:install_dir], "jobs", "angel", "config", "miku.conf")
        .to eq("tenshi\n39\n39.39.39.39\n")
    end

  end

  describe "#sort_release_version" do
    before do
      @nb = NiseBosh::Builder.new(@options, @log)
    end

    it "should sort version numbers" do
      expect(@nb.sort_release_version(%w{1 2 1.1 1.1-dev 33 2.1-dev 33-dev 2.1}))
        .to eq(%w{1 1.1-dev 1.1 2 2.1-dev 2.1 33-dev 33})
    end
  end

  describe "#archive" do
    before do
      @archive_dir = File.join(@tmp_dir, "archive")
      @archive_check_dir = File.join(@tmp_dir, "archive_check")
      setup_directory(@archive_dir)
      setup_directory(@archive_check_dir)
    end

    def check_archive_contents(file_name)
      FileUtils.cd(@archive_check_dir) do
        system("tar xvzf #{file_name} > /dev/null")
        expect_to_same(%W{#{@options[:repo_dir]} dev_releases assets-1.1-dev.yml}, [@archive_check_dir, "release.yml"])
        expect_file_exists(@archive_check_dir, "release", ".final_builds", "jobs", "angel", "1.tgz").to be_true
        expect_file_exists(@archive_check_dir, "release", ".final_builds", "packages", "luca", "1.tgz").to be_true
        expect_file_exists(@archive_check_dir, "release", ".dev_builds", "packages", "miku", "1.1-dev.tgz").to be_true
      end
    end

    it "create archive in current directory" do
      file_name = File.join(@archive_dir, "assets-legna-1.1-dev.tar.gz")
      FileUtils.cd(@archive_dir) do
        @nb.archive("legna", file_name)
        expect(File.exists?(file_name)).to be_true
      end
      check_archive_contents(file_name)
    end

    it "create archive at given file path" do
      file_name = File.join(@archive_dir, "miku.tar.gz")
      @nb.archive("legna", file_name)
      expect(File.exists?(file_name)).to be_true
      check_archive_contents(file_name)
    end

    it "create archive in given directory" do
      file_name = File.join(@archive_dir, "assets-legna-1.1-dev.tar.gz")
      @nb.archive("legna", @archive_dir)
      expect(File.exists?(file_name)).to be_true
      check_archive_contents(file_name)
    end
  end

  describe "#job_exists?" do
    it "should return true when given job exists" do
      expect(@nb.job_exists?("legna")).to be_true
    end

    it "should return false when given job does not exist" do
      expect(@nb.job_exists?("not_exist_job")).to be_false
    end
  end

  describe "#package_exists?" do
    it "should return true when given package exists" do
      expect(@nb.package_exists?(@package)).to be_true
    end

    it "should return false when given package does not exist" do
      expect(@nb.package_exists?("not_exist_package")).to be_false
    end
  end

end
