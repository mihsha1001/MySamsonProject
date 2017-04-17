# frozen_string_literal: true
require_relative "../../test_helper"

SingleCov.covered!

describe Kubernetes::Role do
  include GitRepoTestHelper

  def write_config(file, content)
    Dir.chdir(repo_temp_dir) do
      dir = File.dirname(file)
      Dir.mkdir(dir) if file.include?("/") && !File.exist?(dir)
      File.write(file, content)
    end
    commit
  end

  def commit
    execute_on_remote_repo <<-SHELL
      git add .
      git commit -m "second commit"
    SHELL
  end

  let(:role) { kubernetes_roles(:app_server) }
  let(:project) { role.project }
  let(:config_content) do
    YAML.load_stream(read_kubernetes_sample_file('kubernetes_deployment.yml'))
  end
  let(:config_content_yml) { config_content.map(&:to_yaml).join("\n") }

  describe 'validations' do
    it 'is valid' do
      assert_valid role
    end

    describe "service name" do
      let(:other) { kubernetes_roles(:resque_worker) }

      before do
        other.update_column(:service_name, 'abc')
        role.service_name = 'abc'
      end

      it "stores empty as nil to not run into duplication issues" do
        role.service_name = ''
        assert_valid role
        role.service_name.must_be_nil
      end

      it "is invalid with a already used service name" do
        refute_valid role
      end

      it "is valid with a already used service name that was deleted" do
        other.soft_delete!
        assert_valid role
      end
    end

    describe "name" do
      it 'is invalid with a name we could not use in kubernetes' do
        role.name = 'foo_bar'
        refute_valid role
      end
    end

    describe "resource_name" do
      it "is invalid when blank" do
        role.resource_name = ""
        refute_valid role
      end

      it "is valid when filled with a valid name" do
        role.resource_name = "dfssd"
        assert_valid role
      end

      it "is invalid when it cannot be used in kubernetes" do
        role.resource_name = "sfsdf__F"
        refute_valid role
      end
    end
  end

  describe '.seed!' do
    before do
      create_repo_without_tags
      project.repository_url = repo_temp_dir
      Kubernetes::Role.delete_all
      project.kubernetes_roles.clear
    end

    describe "with a correct role config" do
      before { write_config 'kubernetes/a.yml', config_content_yml }

      it 'creates a role' do
        Kubernetes::Role.seed! project, 'HEAD'
        project.kubernetes_roles.map(&:config_file).must_equal ["kubernetes/a.yml"]
      end

      it 'does not create duplicate roles' do
        Kubernetes::Role.seed! project, 'HEAD'
        Kubernetes::Role.seed! project, 'HEAD'
        project.kubernetes_roles.map(&:config_file).must_equal ["kubernetes/a.yml"]
      end

      it "re-creates deleted roles" do
        Kubernetes::Role.seed! project, 'HEAD'
        project.kubernetes_roles.each(&:soft_delete!)
        Kubernetes::Role.seed! project, 'HEAD'
        project.kubernetes_roles.where(deleted_at: nil).map(&:config_file).must_equal ["kubernetes/a.yml"]
      end
    end

    describe "with a job" do
      before do
        write_config 'kubernetes/a.yml', read_kubernetes_sample_file('kubernetes_job.yml')
      end

      it 'creates a role' do
        Kubernetes::Role.seed! project, 'HEAD'
        role = project.kubernetes_roles.first
        role.name.must_equal 'job-role'
      end
    end

    describe "without a service" do
      before do
        config_content.pop
        write_config 'kubernetes/a.json', config_content.to_json
      end

      it 'creates a role' do
        Kubernetes::Role.seed! project, 'HEAD'
        project.kubernetes_roles.map(&:service_name).must_equal [nil]
      end

      it 'creates a role when another role without service already exists' do
        project.kubernetes_roles.create!(
          config_file: 'sdfsdf.yml',
          name: 'sdfsdf',
          service_name: nil,
          resource_name: 'ssddssd'
        )
        Kubernetes::Role.seed! project, 'HEAD'
        project.kubernetes_roles.map(&:service_name).must_equal [nil, nil]
      end
    end

    describe "with invalid role" do
      before do
        config_content.push config_content.first
        write_config 'kubernetes/a.json', config_content.to_json
      end

      it 'blows up so the controller can show an error' do
        assert_raises Samson::Hooks::UserError do
          Kubernetes::Role.seed! project, 'HEAD'
        end
        project.kubernetes_roles.must_equal []
      end
    end

    it "generates a unique resource_name when metadata.name is already in use" do
      project.update_column(:permalink, 'foo_bar') # check we remove _ correctly
      created = project.kubernetes_roles.create!(role.attributes)
      config_content[0]['metadata']['name'] = created.resource_name
      write_config 'kubernetes/a.json', config_content.to_json

      Kubernetes::Role.seed! project, 'HEAD'

      names = Kubernetes::Role.all.map(&:resource_name)
      names.must_equal ["test-app-server", "foo-bar-test-app-server"]
    end

    it "reads other file types" do
      write_config 'kubernetes/a.json', config_content.to_json
      Kubernetes::Role.seed! project, 'HEAD'
      project.kubernetes_roles.map(&:config_file).must_equal ["kubernetes/a.json"]
    end

    it "does not read other files" do
      write_config 'kubernetes.yml', config_content_yml
      write_config 'foobar/kubernetes.yml', config_content_yml
      e = assert_raises Samson::Hooks::UserError do
        Kubernetes::Role.seed! project, 'HEAD'
      end
      e.message.must_include "No configs found"
      project.kubernetes_roles.must_equal []
    end

    it "warns when nothing was found" do
      e = assert_raises Samson::Hooks::UserError do
        Kubernetes::Role.seed! project, 'DFSDSFSDFD'
      end
      e.message.must_include "No configs found"
    end

    it "can seed duplicate service names" do
      existing_name = config_content.last.fetch('metadata').fetch('name')
      created = project.kubernetes_roles.create!(role.attributes.merge('service_name' => existing_name))
      created.update_column(:project_id, 1234) # make sure we check in glboal scope
      write_config 'kubernetes/a.yml', config_content_yml
      Kubernetes::Role.seed! project, 'HEAD'
      names = Kubernetes::Role.all.map(&:service_name)
      names.last.must_match /#{existing_name}-change-me-\d+/
    end
  end

  describe '.configured_for_project' do
    before do
      create_repo_without_tags
      project.repository_url = repo_temp_dir
      write_config role.config_file, config_content_yml
    end

    it "finds all roles that are deployed" do
      Kubernetes::Role.configured_for_project(project, 'HEAD').must_equal [role]
    end

    describe "with uncommon config location" do
      before do
        execute_on_remote_repo "git rm #{role.config_file}" # remove file from git ls-files
        role.update_column(:config_file, 'foobar/foo.yml')
      end

      it "finds roles outside of the common locations" do
        write_config role.config_file, config_content_yml
        Kubernetes::Role.configured_for_project(project, 'HEAD').must_equal [role]
      end

      it "ignores when the role is configured but not in the repo" do
        Kubernetes::Role.configured_for_project(project, 'HEAD').must_equal []
      end
    end

    it "ignores when a role is in the repo, but not configured" do
      role.destroy!
      Kubernetes::Role.configured_for_project(project, 'HEAD').must_equal []
    end

    it "raises when a role is invalid so the deploy is stopped" do
      assert config_content_yml.sub!('Deployment', 'Broken')
      write_config role.config_file, config_content_yml

      assert_raises Samson::Hooks::UserError do
        Kubernetes::Role.configured_for_project(project, 'HEAD')
      end
    end

    it "ignores deleted roles" do
      other = project.kubernetes_roles.create!(
        config_file: 'foobar/foo.yml', name: 'xasdasd', resource_name: 'dsfsfsdf'
      )
      write_config other.config_file, config_content_yml
      other.soft_delete!

      Kubernetes::Role.configured_for_project(project, 'HEAD').must_equal [role]
    end
  end

  describe '#defaults' do
    before do
      GitRepository.any_instance.stubs(file_content: config_content_yml)
    end

    it "find defaults" do
      role.defaults.must_equal cpu: 0.5, ram: 95, replicas: 2
    end

    it "defaults to 1 replica" do
      assert config_content_yml.sub!('replicas: 2', 'foobar: 3')
      role.defaults.must_equal cpu: 0.5, ram: 95, replicas: 1
    end

    it "does not fail without spec" do
      map = {
        kind: 'ConfigMap',
        metadata: {
          name: 'datadog'
        },
        namespace: 'default',
        labels: {
          project: 'some-project',
          role: 'some-role'
        }
      }.to_yaml
      config_content_yml.prepend("#{map}\n---\n")
      role.defaults.must_equal cpu: 0.5, ram: 95, replicas: 2
    end

    it "finds values for any kind of resource" do
      assert config_content_yml.sub!('Deployment', 'Job')
      assert config_content_yml.sub!(/\n\n---.*/m, '')
      assert config_content_yml.sub!('containers:', "restartPolicy: Never\n      containers:")
      assert role.defaults
    end

    {
      '10000000' => 10,
      '10000000000m' => 10,
      '10000K' => 10,
      '10000Ki' => 10,
      '10M' => 10,
      '10Mi' => 10,
      '10G' => 10 * 1024,
      '10.5G' => 10.5 * 1024,
      '10Gi' => 9537,
    }.each do |ram, expected|
      it "converts memory units #{ram}" do
        assert config_content_yml.sub!('100Mi', ram)
        role.defaults.try(:[], :ram).must_equal expected
      end
    end

    it "ignores unknown units" do
      assert config_content_yml.sub!('100Mi', '200T')
      role.defaults.must_be_nil
    end

    it "ignores when there is no config" do
      GitRepository.any_instance.stubs(file_content: nil)
      role.defaults.must_be_nil
    end

    it "ignores when config is invalid" do
      assert config_content_yml.sub!('Deployment', 'Deploymentx')
      refute role.defaults
    end
  end

  describe "#delete_kubernetes_deploy_group_roles" do
    it "cleanes up configs on delete so other validations do not run in to them" do
      Kubernetes::DeployGroupRole.create!(
        kubernetes_role: role,
        project: project,
        ram: 10,
        replicas: 1,
        cpu: 1,
        deploy_group: deploy_groups(:pod2)
      )
      role.kubernetes_deploy_group_roles.wont_equal []
      role.soft_delete!
      role.reload.kubernetes_deploy_group_roles.must_equal []
    end
  end

  describe "#strip_config_file" do
    it "removes spaces from config files because that happens to often and leads to mysterious bugs" do
      role.config_file = ' whoops '
      role.save!
      role.config_file.must_equal 'whoops'
    end
  end
end
