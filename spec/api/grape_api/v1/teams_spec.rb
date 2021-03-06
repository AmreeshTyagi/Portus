# frozen_string_literal: true

require "rails_helper"

describe API::V1::Teams do
  let!(:admin) { create(:admin) }
  let!(:user) { create(:user) }
  let!(:token) { create(:application_token, user: admin) }
  let!(:user_token) { create(:application_token, user: create(:user)) }
  let!(:hidden_team) do
    create(:team,
           name:   "portus_global_team_1",
           owners: [admin],
           hidden: true)
  end

  before :each do
    @admin_header = build_token_header(token)
    @user_header = build_token_header(user_token)
  end

  context "GET /api/v1/teams" do
    it "returns an empty list" do
      get "/api/v1/teams", nil, @admin_header

      teams = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(teams.length).to eq(0)
    end

    it "returns list of teams" do
      create_list(:team, 5, owners: [admin])
      get "/api/v1/teams", nil, @admin_header

      teams = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(teams.length).to eq(5)
    end
  end

  context "GET /api/v1/teams/:id" do
    it "returns a team" do
      team = create(:team, owners: [admin])
      get "/api/v1/teams/#{team.id}", nil, @admin_header

      team_parsed = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(team_parsed["id"]).to eq(team.id)
      expect(team_parsed["name"]).to eq(team.name)
    end

    it "returns 404 if it doesn't exist" do
      get "/api/v1/teams/222", nil, @admin_header

      expect(response).to have_http_status(:not_found)
    end
  end

  context "GET /api/v1/teams/:id/namespaces" do
    it "returns list of namespaces from a team" do
      team = create(:team, owners: [admin])
      create_list(:namespace, 5, team: team)
      get "/api/v1/teams/#{team.id}/namespaces", nil, @admin_header

      namespaces = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(namespaces.length).to eq(5)
    end
  end

  context "GET /api/v1/teams/:id/members" do
    it "returns list of members from a team" do
      user = create(:user)
      team = create(:team, owners: [admin])
      TeamUser.create(team: team, user: user, role: TeamUser.roles[:viewer])
      get "/api/v1/teams/#{team.id}/members", nil, @admin_header

      members = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(members.length).to eq(2)
    end
  end

  context "DELETE /api/v1/teams/:id/members/:member_id" do
    let(:user) { create(:user) }
    let(:team) { create(:team, owners: [admin]) }

    it "removes member from a team" do
      team_user = TeamUser.create(team: team, user: user, role: TeamUser.roles[:viewer])

      expect(team.team_users.count).to eq(2)

      delete "/api/v1/teams/#{team.id}/members/#{team_user.id}", nil, @admin_header

      expect(response).to have_http_status(:no_content)
      expect(team.team_users.count).to eq(1)
    end

    it "returns 404 if member doesn't exist" do
      team = create(:team, owners: [admin])

      delete "/api/v1/teams/#{team.id}/members/123", nil, @admin_header

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 if team doesn't exist" do
      team_user = TeamUser.create(team: team, user: user, role: TeamUser.roles[:viewer])

      delete "/api/v1/teams/123/members/#{team_user.id}", nil, @admin_header

      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 if removing the only owner of the team" do
      team_user_admin = team.team_users.first
      TeamUser.create(team: team, user: user, role: TeamUser.roles[:contributor])

      delete "/api/v1/teams/#{team.id}/members/#{team_user_admin.id}", nil, @admin_header

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "PUT /api/v1/teams/:id/members/:member_id" do
    let(:user) { create(:user) }
    let(:team) { create(:team, owners: [admin]) }
    let(:data) { { role: "contributor" } }

    it "updates a member's role of a team" do
      team_user = TeamUser.create(team: team, user: user, role: TeamUser.roles[:viewer])

      expect(team_user.role).to eq("viewer")

      put "/api/v1/teams/#{team.id}/members/#{team_user.id}", data, @admin_header

      member = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(member["role"]).to eq("contributor")
    end

    it "returns 400 if data doesn't meet the requirements" do
      put "/api/v1/teams/#{team.id}/members/123", nil, @admin_header

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 404 if member doesn't exist" do
      put "/api/v1/teams/#{team.id}/members/123", data, @admin_header

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 if team doesn't exist" do
      team_user = TeamUser.create(team: team, user: user, role: TeamUser.roles[:viewer])

      put "/api/v1/teams/123/members/#{team_user.id}", data, @admin_header

      expect(response).to have_http_status(404)
    end

    it "returns 422 if trying to demote a portus admin" do
      team_user_admin = team.team_users.first
      TeamUser.create(team: team, user: user, role: TeamUser.roles[:owner])

      put "/api/v1/teams/#{team.id}/members/#{team_user_admin.id}", data, @admin_header

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 if demoting the only owner of the team" do
      owner = create(:user)
      team = create(:team, owners: [owner])
      team_user_owner = team.team_users.first

      delete "/api/v1/teams/#{team.id}/members/#{team_user_owner.id}", nil, @admin_header

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "POST /api/v1/teams/:id/members" do
    let(:user) { create(:user) }
    let(:team) { create(:team, owners: [admin]) }

    it "adds a member to a team and returns it" do
      data = {
        role: "viewer",
        user: user.username
      }

      expect(team.team_users.count).to eq(1)

      post "/api/v1/teams/#{team.id}/members", data, @admin_header

      member = JSON.parse(response.body)
      expect(response).to have_http_status(:created)
      expect(team.team_users.count).to eq(2)
      expect(member["display_name"]).to eq(user.display_username)
      expect(member["role"]).to eq("viewer")
    end

    it "adds portus admin always as owner" do
      another_admin = create(:admin)
      data = {
        role: "viewer",
        user: another_admin.username
      }

      post "/api/v1/teams/#{team.id}/members", data, @admin_header

      member = JSON.parse(response.body)
      expect(response).to have_http_status(:created)
      expect(member["role"]).to eq("owner")
    end

    it "returns 404 if team doesn't exist" do
      data = {
        role: "viewer",
        user: user.username
      }

      post "/api/v1/teams/123/members", data, @admin_header

      expect(response).to have_http_status(404)
    end

    it "returns 404 if user doesn't exist" do
      data = {
        role: "viewer",
        user: "user"
      }

      post "/api/v1/teams/#{team.id}/members", data, @admin_header

      expect(response).to have_http_status(404)
    end

    it "returns 422 if user already belongs to the team" do
      data = {
        role: "viewer",
        user: admin.username
      }

      post "/api/v1/teams/#{team.id}/members", data, @admin_header

      expect(response).to have_http_status(422)
    end

    it "returns 400 if data doesn't meet the requirements" do
      post "/api/v1/teams/#{team.id}/members", nil, @admin_header

      expect(response).to have_http_status(:bad_request)
    end
  end

  context "POST /api/v1/teams" do
    let(:valid_attributes) do
      { name: "qa team", description: "short test description" }
    end

    let(:owner_valid_attributes) do
      { name: "qa team", description: "short test description", owner_id: user.id }
    end

    let(:invalid_attributes) do
      { admin: "not valid" }
    end

    it "creates a team" do
      expect do
        post "/api/v1/teams", valid_attributes, @admin_header
      end.to change(Team, :count).by(1)

      team = Team.last
      team_parsed = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(team_parsed["id"]).to eq(team.id)
      expect(team_parsed["name"]).to eq(team.name)
    end

    it "creates a team even if feature is disabled and admin" do
      APP_CONFIG["user_permission"]["create_team"]["enabled"] = false

      expect do
        post "/api/v1/teams", valid_attributes, @admin_header
      end.to change(Team, :count).by(1)

      team = Team.last
      team_parsed = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(team_parsed["id"]).to eq(team.id)
      expect(team_parsed["name"]).to eq(team.name)
    end

    it "creates a team with different owner" do
      expect do
        post "/api/v1/teams", owner_valid_attributes, @admin_header
      end.to change(Team, :count).by(1)

      team = Team.last
      team_parsed = JSON.parse(response.body)
      expect(response).to have_http_status(:success)
      expect(team_parsed["id"]).to eq(team.id)
      expect(team_parsed["name"]).to eq(team.name)
    end

    it "returns 403 if current user is not admin when creating a team with different owner" do
      post "/api/v1/teams", owner_valid_attributes, @user_header

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 400 if invalid params" do
      post "/api/v1/teams", invalid_attributes, @admin_header

      expect(response).to have_http_status(:bad_request)
    end

    it "returns a 400 for malformed JSON" do
      @admin_header = @admin_header.merge(
        "CONTENT_TYPE" => "application/json",
        "ACCEPT"       => "application/json"
      )
      post "/api/v1/teams", "{", @admin_header
      expect(response).to have_http_status(:bad_request)

      resp = JSON.parse(response.body)
      expect(resp["message"]).to match(/There was a problem in the JSON you submitted/)
    end

    it "returns 422 if invalid values" do
      post "/api/v1/teams", { name: "" }, @admin_header

      parsed = JSON.parse(response.body)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(parsed["message"]["name"].first).to include("can't be blank")
    end

    it "returns 403 if non-admins try to create a Team" do
      APP_CONFIG["user_permission"]["create_team"]["enabled"] = false

      expect do
        post "/api/v1/teams", valid_attributes, @user_header
      end.to change(Team, :count).by(0)

      expect(response).to have_http_status(:forbidden)
    end

    it "tracks the creations of new teams" do
      expect do
        post "/api/v1/teams", valid_attributes, @admin_header
      end.to change(PublicActivity::Activity, :count).by(1)

      team = Team.last
      team_creation_activity = PublicActivity::Activity.find_by(key: "team.create")
      expect(team_creation_activity.owner).to eq(admin)
      expect(team_creation_activity.trackable).to eq(team)
    end
  end
end
