defmodule LivebookWeb.Integration.Hub.DeploymentGroupTest do
  use Livebook.TeamsIntegrationCase, async: true

  import Livebook.TestHelpers
  import Phoenix.LiveViewTest

  alias Livebook.Teams.DeploymentGroup

  @moduletag teams_for: :user
  setup :teams

  @moduletag subscribe_to_hubs_topics: [:crud, :connection, :secrets, :file_systems]
  @moduletag subscribe_to_teams_topics: [:clients, :agents, :app_deployments, :deployment_groups]

  test "creates a deployment group", %{conn: conn, team: team} do
    deployment_group =
      build(:deployment_group,
        mode: :offline,
        hub_id: team.id,
        url: "http://example.com"
      )

    name = deployment_group.name
    url = deployment_group.url

    attrs = %{
      deployment_group: %{
        name: deployment_group.name,
        value: deployment_group.mode,
        hub_id: deployment_group.hub_id,
        url: url
      }
    }

    {:ok, view, _html} = live(conn, ~p"/hub/#{team.id}")

    assert view
           |> element("#add-deployment-group")
           |> render_click(%{}) =~ "Add deployment group"

    view
    |> element("#deployment-group-form")
    |> render_change(attrs)

    refute view
           |> element("#deployment-group-form button[disabled]")
           |> has_element?()

    view
    |> element("#deployment-group-form")
    |> render_submit(attrs)

    assert_receive {:deployment_group_created,
                    %DeploymentGroup{name: ^name, url: ^url} = deployment_group}

    assert_patch(view, "/hub/#{team.id}")
    assert render(view) =~ "Deployment group added successfully"
    assert deployment_group in Livebook.Teams.get_deployment_groups(team)

    # Guarantee it shows the error from API
    {:ok, view, _html} = live(conn, ~p"/hub/#{team.id}")

    assert view
           |> element("#add-deployment-group")
           |> render_click(%{}) =~ "Add deployment group"

    assert view
           |> element("#deployment-group-form")
           |> render_submit(attrs) =~ "has already been taken"

    invalid_attrs = %{
      deployment_group: %{
        name: "other-name",
        value: deployment_group.mode,
        hub_id: deployment_group.hub_id,
        url: "http://not a valid url"
      }
    }

    assert view
           |> element("#deployment-group-form")
           |> render_submit(invalid_attrs) =~ "must be a well-formed URL"

    invalid_attrs = %{
      deployment_group: %{
        name: "other-name",
        value: deployment_group.mode,
        hub_id: deployment_group.hub_id,
        url: "url.without.scheme.com"
      }
    }

    assert view
           |> element("#deployment-group-form")
           |> render_submit(invalid_attrs) =~
             "must start with &quot;http://&quot; or &quot;https://&quot;"
  end

  test "creates a secret", %{conn: conn, team: team, node: node, org: org} do
    deployment_group = TeamsRPC.create_deployment_group(node, org: org)
    id = to_string(deployment_group.id)
    assert_receive {:deployment_group_created, %{id: ^id}}

    secret = build(:secret, hub_id: team.id, deployment_group_id: id)

    {:ok, view, _html} = live(conn, ~p"/hub/#{team.id}")

    attrs = %{
      secret: %{
        name: secret.name,
        value: secret.value,
        hub_id: secret.hub_id,
        deployment_group_id: secret.deployment_group_id
      }
    }

    refute render(view) =~ secret.name

    view
    |> element("#hub-deployment-group-#{id} [aria-label=\"add secret\"]", "Add secret")
    |> render_click(%{})

    assert_patch(view, ~p"/hub/#{team.id}/groups/#{id}/secrets/new")
    assert render(view) =~ "Add secret"

    view
    |> element("#deployment-group-secrets-form")
    |> render_change(attrs)

    refute view
           |> element("#deployment-group-secrets-form button[disabled]")
           |> has_element?()

    view
    |> element("#deployment-group-secrets-form")
    |> render_submit(attrs)

    assert_receive {:deployment_group_updated,
                    %Livebook.Teams.DeploymentGroup{id: ^id, secrets: [^secret]} =
                      deployment_group}

    assert_patch(view, ~p"/hub/#{team.id}")
    assert render(view) =~ "Secret #{secret.name} added successfully"
    assert render(element(view, "#hub-deployment-group-#{id}")) =~ secret.name
    assert secret in deployment_group.secrets

    # Guarantee it shows the error from API
    {:ok, view, _html} = live(conn, ~p"/hub/#{team.id}/groups/#{id}/secrets/new")

    assert view
           |> element("#deployment-group-secrets-form")
           |> render_submit(attrs) =~ "has already been taken"
  end

  test "updates an existing secret",
       %{conn: conn, team: team, node: node, org: org, org_key: org_key} do
    deployment_group = TeamsRPC.create_deployment_group(node, org: org)
    secret = TeamsRPC.create_deployment_group_secret(node, team, org_key, deployment_group)
    id = to_string(deployment_group.id)

    assert_receive {:deployment_group_updated,
                    %Livebook.Teams.DeploymentGroup{id: ^id, secrets: [^secret]}}

    {:ok, view, _html} = live(conn, ~p"/hub/#{team.id}")

    assert view
           |> element("#hub-deployment-group-#{id} [aria-label=\"edit #{secret.name}\"]")
           |> render_click() =~ "Edit secret"

    assert_patch(view, ~p"/hub/#{team.id}/groups/#{id}/secrets/edit/#{secret.name}")

    attrs = %{
      secret: %{
        name: secret.name,
        value: secret.value,
        hub_id: secret.hub_id
      }
    }

    new_value = "new_value"

    view
    |> element("#deployment-group-secrets-form")
    |> render_change(attrs)

    refute view
           |> element("#deployment-group-secrets-form button[disabled]")
           |> has_element?()

    view
    |> element("#deployment-group-secrets-form")
    |> render_submit(put_in(attrs.secret.value, new_value))

    updated_secret = %{secret | value: new_value}

    assert_receive {:deployment_group_updated,
                    %Livebook.Teams.DeploymentGroup{id: ^id, secrets: [^updated_secret]} =
                      deployment_group}

    assert_patch(view, "/hub/#{team.id}")
    assert render(view) =~ "Secret #{secret.name} updated successfully"
    assert render(element(view, "#hub-deployment-group-#{id}")) =~ secret.name
    assert updated_secret in deployment_group.secrets
  end

  test "deletes an existing secret",
       %{conn: conn, team: team, node: node, org: org, org_key: org_key} do
    deployment_group = TeamsRPC.create_deployment_group(node, org: org)
    secret = TeamsRPC.create_deployment_group_secret(node, team, org_key, deployment_group)
    id = to_string(deployment_group.id)

    {:ok, view, _html} = live(conn, ~p"/hub/#{team.id}")

    view
    |> element("#hub-deployment-group-#{id} [aria-label=\"delete #{secret.name}\"]")
    |> render_click()

    render_confirm(view)

    assert_receive {:deployment_group_updated,
                    %Livebook.Teams.DeploymentGroup{id: ^id, secrets: []}}

    assert_patch(view, ~p"/hub/#{team.id}")
    assert render(view) =~ "Secret #{secret.name} deleted successfully"
    refute render(element(view, "#hub-deployment-group-#{id}")) =~ secret.name
  end

  test "shows the agent count", %{conn: conn, team: team, node: node, org: org} do
    deployment_group = TeamsRPC.create_deployment_group(node, org: org)
    id = to_string(deployment_group.id)
    {:ok, view, _html} = live(conn, ~p"/hub/#{team.id}")

    assert view
           |> element("#hub-deployment-group-#{id} [aria-label=\"app servers\"]")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.text()
           |> String.trim() == "0"

    simulate_agent_join(team, deployment_group)

    assert view
           |> element("#hub-deployment-group-#{id} [aria-label=\"app servers\"]")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.text()
           |> String.trim() == "1"
  end

  @tag :tmp_dir
  test "shows the app deployed count",
       %{conn: conn, team: team, node: node, org: org, tmp_dir: tmp_dir} do
    deployment_group = TeamsRPC.create_deployment_group(node, org: org)
    id = to_string(deployment_group.id)
    hub_id = team.id

    {:ok, view, _html} = live(conn, ~p"/hub/#{team.id}")

    refute_received {:app_deployment_started, %{deployment_group_id: ^id, hub_id: ^hub_id}}

    assert view
           |> element("#hub-deployment-group-#{id} [aria-label=\"apps deployed\"]")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.text()
           |> String.trim() == "0"

    app_settings = %{Livebook.Notebook.AppSettings.new() | slug: Livebook.Utils.random_short_id()}

    notebook = %{
      Livebook.Notebook.new()
      | app_settings: app_settings,
        name: "MyNotebook",
        hub_id: team.id,
        deployment_group_id: id
    }

    files_dir = Livebook.FileSystem.File.local(tmp_dir)

    {:ok, app_deployment} = Livebook.Teams.AppDeployment.new(notebook, files_dir)
    :ok = Livebook.Teams.deploy_app(team, app_deployment)

    assert_receive {:app_deployment_started, %{deployment_group_id: ^id}}, 2_000

    assert view
           |> element("#hub-deployment-group-#{id} [aria-label=\"apps deployed\"]")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.text()
           |> String.trim() == "1"
  end

  test "shows the environment variables count", %{conn: conn, team: team, node: node, org: org} do
    deployment_group = TeamsRPC.create_deployment_group(node, org: org)
    id = to_string(deployment_group.id)

    assert_receive {:deployment_group_created, %{id: ^id, environment_variables: []}}

    {:ok, view, _html} = live(conn, ~p"/hub/#{team.id}")

    assert view
           |> element("#hub-deployment-group-#{id} [aria-label=\"environment variables\"]")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.text()
           |> String.trim() == "0"

    TeamsRPC.create_environment_variable(node, deployment_group: deployment_group)
    assert_receive {:deployment_group_updated, %{id: ^id, environment_variables: [_]}}

    assert view
           |> element("#hub-deployment-group-#{id} [aria-label=\"environment variables\"]")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.text()
           |> String.trim() == "1"
  end
end
