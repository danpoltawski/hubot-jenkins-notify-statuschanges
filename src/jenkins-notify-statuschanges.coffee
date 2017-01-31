# Description
#   Notify if jenkins job status changes
#
# Configuration:
#   JENKINS_NOTIFY_ROOMS
#
# Commands:
#
# Notes:
#   <optional notes required for the script>
#
# Author:
#   Dan Poltawski <dan@moodle.com>

urllib = require 'url'
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

module.exports = (robot) ->
    if !process.env.JENKINS_NOTIFY_ROOMS?
        throw new Error('JENKINS_NOTIFY_ROOMS is not set.')
    
    room_config = JSON.parse process.env.JENKINS_NOTIFY_ROOMS
    if !Object.keys(room_config).length
        throw new Error('JENKINS_NOTIFY_ROOMS is empty')

    robot.router.post '/hubot/jenkinsnotify', (req, res) ->
        data = if req.body.payload? then JSON.parse req.body.payload else req.body

        if !data.build? || !data.build.phase? || !data.build['full_url']
            res.status(400).send('Bad request')
            return

        rooms_to_inform = Object.keys(room_config).filter (url) ->
            return data.build['full_url'].indexOf(url) == 0
        
        if !rooms_to_inform.length
            robot.logger.info("Cant find room configuration for #{data.build['full_url']}")
            res.status(404).send('Not found')
            return;
    
        roomid = room_config[rooms_to_inform[0]]

        if data.build.phase != 'COMPLETED'
            res.status(200).send("Ignoring phrase #{data.build.phase}")
            return

        if !data.build.status?
            res.status(500).send('No status provided')
            return
    
        status = data.build.status
        storagekey = 'jenkins-build-' + data.url
        lastKnownState = robot.brain.get(storagekey)

        shouldNotify = false
        if lastKnownState != status
            robot.logger.info 'State of '+data.url+' changed'
            if lastKnownState
                shouldNotify = true
            else if status != "SUCCESS"
                shouldNotify = true
            else
                shouldNotify = false
        else 
            robot.logger.info 'State of '+data.url+' same'
        
        robot.brain.set storagekey, status

        emoji = ""
        friendlytext = ""
        extrainfo = ""
        urlinfo = urllib.parse data.build['full_url']
        # Fix a particular markdown annoyance..
        fullurl = data.build['full_url'].replace(/\(/g, "%28").replace(/\)/g, "%29");

        switch status
            when "FAILURE"
                emoji = "⛔️"
                friendlytext = "has failed"
                if data.build.log
                    log = extractRelevantLogLines data.build.log
                    extrainfo += "```\n#{log}\n```"
                extrainfo += "[Console Output for ##{data.build.number}](#{fullurl}console)"
            when "SUCCESS"
                emoji = "✅"
                friendlytext = "has passed"
            when "ABORTED"
                emoji = "🛑"
                friendlytext = "was aborted"
            when "UNSTABLE"
                emoji = "⚠️️"
                friendlytext = "is unstable"

        if shouldNotify
            message = "#{emoji} [#{data.name}] [build ##{data.build.number}](#{fullurl}) #{friendlytext} on #{urlinfo.hostname}"
            message += "\n#{extrainfo}" if extrainfo?
            robot.messageRoom roomid, message

        res.status(200).send('OK')