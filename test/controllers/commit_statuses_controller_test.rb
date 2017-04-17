# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe CommitStatusesController do
  as_a_viewer do
    unauthorized :get, :show, stage_id: 'staging', project_id: 'foo', id: 'test/test'
  end

  as_a_project_deployer do
    describe '#show' do
      let(:stage) { stages(:test_staging) }
      let(:project) { projects(:test) }
      let(:valid_params) { {project_id: project.to_param, stage_id: stage.to_param, id: 'test/test'} }

      it "fails with unknown project" do
        assert_raises ActiveRecord::RecordNotFound do
          get :show, params: valid_params.merge(project_id: 'bar')
        end
      end

      it "fails with unknown stage" do
        stage.update_column(:project_id, 3)
        assert_raises(ActiveRecord::RecordNotFound) { get :show, params: valid_params }
      end

      describe 'valid' do
        let(:commit_status_data) do
          {
            status: 'pending',
            status_list: [{ status: 'pending', description: 'the Travis build is still running' }]
          }
        end

        before do
          CommitStatus.stubs(new: stub(commit_status_data))
          get :show, params: valid_params
        end

        it 'responds ok' do
          response.status.must_equal(200)
        end

        it 'responds with the status' do
          response.body.must_equal(JSON.dump(commit_status_data))
        end
      end
    end
  end
end
