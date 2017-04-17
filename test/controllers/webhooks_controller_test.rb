# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe WebhooksController do
  let(:project) { projects(:test) }
  let(:stage) { stages(:test_staging) }
  let(:webhook) { project.webhooks.create!(stage: stage, branch: 'master', source: 'code') }

  as_a_viewer do
    unauthorized :get, :index, project_id: :foo
    unauthorized :post, :create, project_id: :foo
    unauthorized :delete, :destroy, project_id: :foo, id: 1
  end

  as_a_project_deployer do
    describe '#index' do
      before { webhook } # trigger create

      it 'renders' do
        get :index, params: {project_id: project.to_param}
        assert_template :index
      end

      it "does not blow up with deleted stages" do
        stage.soft_delete!
        get :index, params: {project_id: project}
        assert_template :index
      end
    end

    describe '#create' do
      let(:params) { { branch: "master", stage_id: stage.id, source: 'any' } }

      it "redirects to index" do
        post :create, params: {project_id: project.to_param, webhook: params}
        refute flash[:alert]
        assert_redirected_to project_webhooks_path(project)
      end

      it "shows validation errors" do
        webhook # already exists
        post :create, params: {project_id: project.to_param, webhook: params}
        flash[:alert].must_include 'branch'
        assert_template :index
        response.body.scan("<strong>#{params[:branch]}</strong>").count.must_equal 1 # do not show the built hook
      end
    end

    describe "#destroy" do
      it "deletes the hook" do
        delete :destroy, params: {project_id: project.to_param, id: webhook.id}
        assert_raises(ActiveRecord::RecordNotFound) { Webhook.find(webhook.id) }
        assert_redirected_to project_webhooks_path(project)
      end
    end
  end
end
