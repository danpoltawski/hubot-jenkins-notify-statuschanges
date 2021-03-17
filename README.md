# hubot-jenkins-notify-statuschanges

A hubot plugin to notify a room if jenkins job status changes.

This script provies a HTTP endpoint `/hubot/jenkinsnotify` which is designed to work with the Jenkins [Notification plugin](https://wiki.jenkins.io/display/JENKINS/Notification+Plugin). When a job status changes then the configured chat room will be notified about the job.


## Environment variables

### `HUBOT_JENKINS_NOTIFY_ROOMS`
Contains a JSON object of key and values, the key is the url of the Jenkins server and the value is the room which message should be sent from.
```
HUBOT_JENKINS_NOTIFY_ROOMS="{\"https://ci.example.org\": \"#developers\"}"
```

### `HUBOT_JENKINS_SKIP_NOTIFICATION`
Contains a JSON array of pairs containing state changes (before after) that should not lead to notification.
```
HUBOT_JENKINS_SKIP_NOTIFICATION="[ [ \"SUCCESS\", \"UNSTABLE\" ], [ \"FAILURE\", \"ABORTED\" ] ]"
```

## Notifying when state hasn't changed

The url param `alwaysinform` can be set to 1 to ensure that any notifications will be reported to the chatroom even if the state is the same as previously.

## Startup

When hubot starts up, this plugin will attempt to connect to all the configured jenkins servers on their public API and request job status. The job status will be immediately reported to the chatroom.

See [`src/jenkins-notify-statuschanges.coffee`](src/jenkins-notify-statuschanges.coffee) for full documentation.

## Installation

In hubot project repo, run:

`npm install hubot-jenkins-notify-statuschanges --save`

Then add **hubot-jenkins-notify-statuschanges** to your `external-scripts.json`:

```json
[
  "hubot-jenkins-notify-statuschanges"
]
```

## NPM Module

https://www.npmjs.com/package/hubot-jenkins-notify-statuschanges
