#!/usr/bin/env node
/**
 * Renders the Slack message for one "Deploy & run E2E" run.
 *
 *   node scripts/nightly-notify/main.mjs <reports-dir>
 *
 * Everything else comes from the environment so the workflow can pass GitHub
 * context without quoting it into an argument list. Locally, a directory of
 * downloaded `ctrf-e2e-shard-*` artifacts is enough:
 *
 *   EXPECTED_SHARDS='[1,2,3]' node scripts/nightly-notify/main.mjs ./artifacts
 *
 * Writes `message` and `outcome` to $GITHUB_OUTPUT when running in Actions, and
 * always prints the message, so a failure to reach Slack still leaves the
 * result in the job log.
 */
import fs from 'node:fs'
import crypto from 'node:crypto'

import {
  readShardReports,
  renderSlackMessage,
  stageResultsFromNeeds,
  summarize
} from './report.mjs'

const parseJson = (value, fallback) =>
  value === undefined || value === '' ? fallback : JSON.parse(value)

const reportsDir = process.argv[2]
if (reportsDir === undefined) {
  console.error('Usage: main.mjs <reports-dir>')
  process.exit(2)
}

const summary = summarize({
  // A stage that failed before the fan-out leaves no artifacts to download at
  // all, so a missing directory is a legitimate state, not an error.
  shardReports: fs.existsSync(reportsDir) ? readShardReports(reportsDir) : new Map(),
  expectedShards: parseJson(process.env.EXPECTED_SHARDS, []),
  // The whole `needs` context, so the workflow states its upstream jobs once.
  stageResults: stageResultsFromNeeds(parseJson(process.env.NEEDS, {})),
  testJobResult: process.env.TEST_JOB_RESULT ?? 'success'
})

const message = renderSlackMessage(summary, {
  eventName: process.env.EVENT_NAME,
  actor: process.env.ACTOR,
  coreBranch: process.env.CORE_BRANCH,
  coreImageTag: process.env.CORE_IMAGE_TAG,
  runUrl: process.env.RUN_URL,
  regressionEnabled: process.env.REGRESSION_ENABLED === 'true'
})

console.log(message)

if (process.env.GITHUB_OUTPUT !== undefined) {
  const delimiter = `ghadelimiter_${crypto.randomUUID()}`
  fs.appendFileSync(
    process.env.GITHUB_OUTPUT,
    `outcome=${summary.outcome}\nmessage<<${delimiter}\n${message}\n${delimiter}\n`
  )
}
