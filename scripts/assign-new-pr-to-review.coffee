# Description:
#   Script that listens to new GitHub pull requests
#   and assigns them to the REVIEW column on the "Pipeline for QA" project

module.exports = (robot) ->

  projectBoardName = "Pipeline for QA"
  reviewColumnName = "REVIEW"
  notifyRoomName = "core"

  GitHubApi = require("github")

  robot.on "github-repo-event", (repo_event) ->
    githubPayload = repo_event.payload

    switch(repo_event.eventType)
      when "pull_request"
        # Make sure we don't listen to our own messages
        return if equalsRobotName(robot, githubPayload.pull_request.user.login)

        token = process.env.HUBOT_GITHUB_TOKEN
        return console.error "No Github token provided to Hubot" unless token

        action = githubPayload.action
        if action == "opened"
          # A new PR was opened
          github = new GitHubApi { version: "3.0.0" }
          github.authenticate({
            type: "token",
            token: token
          })

          assignPullRequestToReview github, githubPayload, robot

assignPullRequestToReview = (github, githubPayload, robot) ->
  ownerName = githubPayload.repository.owner.login
  repoName = githubPayload.repository.name
  prNumber = githubPayload.pull_request.number
  robot.logger.info "assignPullRequestToReview - Handling Pull Request ##{prNumber} on repo #{ownerName}/#{repoName}"

  # Fetch repo projects
  # TODO: The repo project and project column info should be cached in order to improve performance and reduce roundtrips
  github.projects.getRepoProjects {
    owner: ownerName,
    repo: repoName,
    state: "open"
  }, (err, ghprojects) ->
    if err
      robot.logger.error "Couldn't fetch the github projects for repo: #{err}",
        ownerName, repoName
      return

    # Find "Pipeline for QA" project
    project = findProject ghprojects.data, projectBoardName
    if !project
      robot.logger.warn "Couldn't find project #{projectBoardName}" +
        " in repo #{ownerName}/#{repoName}"
      return
    
    robot.logger.debug "Fetched #{project.name} project (#{project.id})"

    # Fetch REVIEW column ID
    github.projects.getProjectColumns { project_id: project.id }, (err, ghcolumns) ->
      if err
        robot.logger.error "Couldn't fetch the github columns for project: #{err}",
          ownerName, repoName, project.id
        return

      column = findColumn ghcolumns.data, reviewColumnName
      if !column
        robot.logger.warn "Couldn't find #{projectBoardName} column" +
          " in project #{project.name}"
        return
      
      robot.logger.debug "Fetched #{column.name} column (#{column.id})"

      # Create project card for the PR in the REVIEW column
      github.projects.createProjectCard {
        column_id: column.id,
        content_type: 'PullRequest',
        content_id: githubPayload.pull_request.id
        }, (err, ghcard) ->
        if err
          robot.logger.error "Couldn't create project card for the PR: #{err}",
            column.id, githubPayload.pull_request.id
          return

        robot.logger.debug "Created card: #{ghcard.data.url}", ghcard.data.id

        # Send message to Slack
        robot.messageRoom notifyRoomName,
          "Moved PR #{githubPayload.pull_request.number} to " +
          "#{reviewColumnName} in #{projectBoardName} project"


findProject = (projects, name) ->
  for idx, project of projects
    return project if project.name == name
  return null

findColumn = (columns, name) ->
  for idx, column of columns
    return column if column.name == name
  return null

equalsRobotName = (robot, str) ->
  return getRegexForRobotName(robot).test(str)

RegExp cachedRobotNameRegex = null
getRegexForRobotName = (robot) ->
  # This comes straight out of Hubot's Robot.coffee
  # - they didn't get a nice way of extracting that method though
  if !cachedRobotNameRegex
    name = robot.name.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, '\\$&')

    if robot.alias
      alias = robot.alias.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, '\\$&')
      namePattern = "^\\s*[@]?(?:#{alias}|#{name})"
    else
      namePattern = "^\\s*[@]?#{name}"
    cachedRobotNameRegex = new RegExp(namePattern, 'i')
  return cachedRobotNameRegex
