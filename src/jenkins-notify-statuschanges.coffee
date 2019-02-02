# Description
#   Notify if jenkins job status changes
#
# Configuration:
#   HUBOT_JENKINS_NOTIFY_ROOMS
#
# Commands:
#
# Notes:
#   <optional notes required for the script>
#
# Author:
#   Dan Poltawski <dan@moodle.com>

urllib = require 'url'
request = require 'request'

if !process.env.HUBOT_JENKINS_NOTIFY_ROOMS?
    throw new Error('HUBOT_JENKINS_NOTIFY_ROOMS is not set.')

room_config = JSON.parse process.env.HUBOT_JENKINS_NOTIFY_ROOMS
if !Object.keys(room_config).length
    throw new Error('HUBOT_JENKINS_NOTIFY_ROOMS is empty')

skip_config = []
if process.env.HUBOT_JENKINS_SKIP_NOTIFICATION?
    skip_config = JSON.parse process.env.HUBOT_JENKINS_SKIP_NOTIFICATION

getBuildStatusFromServer = (robot, server, roomid) ->
    options = {url: "#{server}/api/json?depth=1&tree=jobs[displayName,url,lastBuild[result,number]]", timeout: 3000}

    request options, (err, resp, body) ->
        if err
            robot.logger.info "Failed getting status from #{server}"
            return
        try
            data = JSON.parse(body)
            failedjobs = (job for job in data.jobs when job.lastBuild != null and job.lastBuild.result != "SUCCESS")
        catch
            failedjobs = []

        failedbuilds = []
        for job in failedjobs
            robot.brain.set job.url, job.lastBuild.result
            build = {'full_url': "#{job.url}/#{job.lastBuild.number}", 'status': job.lastBuild.result, 'number':job.lastBuild.number}
            failedbuilds.push generateRoomMessage(job.displayName, build)

        if failedbuilds.length > 0
            robot.messageRoom roomid, "Bot has restarted - refreshed #{server} status:\n" + failedbuilds.join('\n')

extractRelevantLogLines = (log) ->
    lines = log.split('\n');
    logs = []
    for logline in lines
        if logline.match(/^\[...truncated (.*)...]$/)
            continue
        if logline.match(/^Build step (.*) marked build as failure$/)
            # End of relevant log lines
            return logs.join('\n')
        if logline.match(/^Notifying endpoint/)
            return logs.join('\n')

        logs.push logline

    return logs.join('\n')

generateRoomMessage = (name, build) ->
    emoji = ""
    friendlytext = ""
    extrainfo = ""
    # Fix a particular markdown annoyance..
    fullurl = build['full_url'].replace(/\(/g, "%28").replace(/\)/g, "%29")

    switch build.status
        when "FAILURE"
            emoji = "⛔️"
            friendlytext = "has failed"
            if build.log
                log = extractRelevantLogLines build.log
                extrainfo += "```\n#{log}\n```"
            extrainfo += "[Console Output for ##{build.number}](#{fullurl}console)"
        when "SUCCESS"
            emoji = "✅"
            friendlytext = "has passed"
        when "ABORTED"
            emoji = "🛑"
            friendlytext = "was aborted"
        when "UNSTABLE"
            emoji = "⚠️️"
            friendlytext = "is unstable"

    urlinfo = urllib.parse build['full_url']
    message = "#{emoji} [#{name}] [build ##{build.number}](#{fullurl}) #{friendlytext} on #{urlinfo.hostname}"
    message += "\n#{extrainfo}" if extrainfo
    return message

module.exports = (robot) ->

    for server, roomid of room_config
        getBuildStatusFromServer(robot, server, roomid)

    robot.router.post '/hubot/jenkinsnotify', (req, res) ->
        data = if req.body.payload? then JSON.parse req.body.payload else req.body

        if !data.build? or !data.build.phase? or !data.build['full_url']
            res.status(400).send('Bad request')
            return

        servername = data.build['full_url'].replace("/#{data.url}#{data.build.number}/", '')

        roomid = room_config[servername]
        if !roomid
            robot.logger.info("Cant find room configuration for #{servername}")
            res.status(404).send('Not found')
            return;

        if data.build.phase isnt 'COMPLETED'
            res.status(200).send("Ignoring phrase #{data.build.phase}")
            return

        if !data.build.status?
            res.status(500).send('No status provided')
            return

        status = data.build.status
        key = "#{servername}/#{data.url}"
        lastKnownState = robot.brain.get(key)
        robot.brain.set key, status

        skippable = skip_config.some (x) -> JSON.stringify(x) is JSON.stringify([lastKnownState, status])

        shouldNotify = false
        actioninfo = "no notification sent."
        if lastKnownState isnt status
            if skippable
                actioninfo = "skipping notification."
            else if lastKnownState
                actioninfo = "notifying as state changed."
                shouldNotify = true
            else if status isnt "SUCCESS"
                actioninfo = "notifying as non-success state."
                shouldNotify = true
        else if req.query.alwaysinform and status isnt "SUCCESS"
            actioninfo = "notifying as 'alwaysinform' set."
            shouldNotify = true

        robot.logger.info "#{key} state was '#{lastKnownState}' now '#{status}' #{actioninfo}"

        if shouldNotify
            robot.messageRoom roomid, generateRoomMessage(data.name, data.build)

        res.status(200).send('OK')
