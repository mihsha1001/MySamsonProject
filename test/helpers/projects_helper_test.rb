# frozen_string_literal: true
# rubocop:disable Metrics/LineLength
require_relative '../test_helper'

SingleCov.covered!

describe ProjectsHelper do
  let(:project) { projects(:test) }
  let(:stage) { stages(:test_staging) }

  describe "#star_link" do
    let(:current_user) { users(:admin) }

    it "star a project" do
      current_user.expects(:starred_project?).returns(false)
      link = star_for_project(project)
      link.must_include %(href="/projects/#{project.to_param}/stars")
      link.must_include "Star this project"
    end

    it "unstar a project" do
      current_user.expects(:starred_project?).returns(true)
      link = star_for_project(project)
      link.must_include %(href="/projects/#{project.to_param}/stars")
      link.must_include "Unstar this project"
    end
  end

  describe "#deployment_alert_title" do
    it 'returns the deployment alert data' do
      job = project.jobs.create!(command: 'cat foo', user: users(:deployer), status: 'failed')
      deploy = stage.deploys.create!(reference: 'master', job: job, project: project)
      expected_title = "#{deploy.updated_at.strftime('%Y/%m/%d %H:%M:%S')} Last deployment failed! #{deploy.user.name} failed to deploy '#{deploy.reference}'"
      deployment_alert_title(stage.last_deploy).must_equal(expected_title)
    end
  end

  describe "#job_state_class" do
    let(:job) { jobs(:succeeded_test) }

    it "is success when succeeded" do
      job_state_class(job).must_equal 'success'
    end

    it "is failed otherwise" do
      job.status = 'pending'
      job_state_class(job).must_equal 'failed'
    end
  end

  describe "#admin_for_project?" do
    let(:current_user) { users(:admin) }

    it "works" do
      @project = projects(:test)
      admin_for_project?.must_equal true
    end
  end

  describe "#deployer_for_project?" do
    let(:current_user) { users(:deployer) }

    it "works" do
      @project = projects(:test)
      deployer_for_project?.must_equal true
    end
  end

  describe "#repository_web_link" do
    let(:current_user) { users(:admin) }

    def config_mock
      Rails.application.config.samson.github.stub(:web_url, "github.com") do
        Rails.application.config.samson.gitlab.stub(:web_url, "localhost") do
          yield
        end
      end
    end

    it "makes github repository web link" do
      config_mock do
        project = projects(:test)
        project.name = "Github Project"
        project.repository_url = "https://github.com/bar/foo.git"

        link = repository_web_link(project)
        assert_includes link, "View repository on GitHub"
      end
    end

    it "makes gitlab repository web link" do
      config_mock do
        project = projects(:test)
        project.name = "Gitlab Project"
        project.repository_url = "http://localhost/bar/foo.git"

        link = repository_web_link(project)
        assert_includes link, "View repository on Gitlab"
      end
    end

    it "makes github repository web link" do
      config_mock do
        project = projects(:test)
        link = repository_web_link(project)
        assert_equal link, ""
      end
    end
  end
end
