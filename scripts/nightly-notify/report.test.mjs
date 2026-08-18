import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

import {
  isRegressionSpec,
  readShardReports,
  renderSlackMessage,
  stageResultsFromNeeds,
  summarize,
  toSpecPath
} from './report.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))

const RUNNER_PREFIX =
  '/home/runner/work/opencrvs-testland-infrastructure/opencrvs-testland-infrastructure/'

/**
 * Builds a CTRF report of the shape playwright-ctrf-json-reporter writes: one
 * entry per test carrying its *final* attempt, summary times in milliseconds.
 */
function ctrfReport(tests, { start = 1_755_043_200_000, durationMs = 600_000 } = {}) {
  const counted = (status) => tests.filter((test) => test.status === status).length
  return {
    results: {
      tool: { name: 'playwright' },
      summary: {
        tests: tests.length,
        passed: counted('passed'),
        failed: counted('failed'),
        pending: 0,
        skipped: counted('skipped'),
        other: 0,
        start,
        stop: start + durationMs,
        suites: tests.length
      },
      tests: tests.map((test) => ({
        name: test.name ?? 'a test',
        status: test.status,
        duration: 1000,
        rawStatus: test.status,
        tags: [],
        type: 'e2e',
        filePath: RUNNER_PREFIX + test.spec,
        retries: test.flaky === true ? 1 : 0,
        flaky: test.flaky === true,
        steps: [],
        suite: test.spec
      }))
    }
  }
}

const STANDARD_SPEC = 'packages/testland/e2e/testcases/birth/1-birth-event-declaration.spec.ts'
const OTHER_STANDARD_SPEC = 'packages/testland/e2e/testcases/death/2-death-declaration.spec.ts'
const REGRESSION_SPEC =
  'packages/testland/e2e/testcases/qa-testrail-testcases/Regression-Test-Data/Birth/1.declare-community-leader-residential-birth.spec.ts'

const passing = (spec, name) => ({ spec, status: 'passed', name })
const failing = (spec, name) => ({ spec, status: 'failed', name })

/** Writes reports into the layout `actions/download-artifact` produces: one
 * directory per artifact, named `ctrf-e2e-shard-<n>-<run>-<attempt>`. */
function writeReportsDir(reportsByShard) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nightly-notify-'))
  for (const [shard, report] of Object.entries(reportsByShard)) {
    const artifactDir = path.join(dir, `ctrf-e2e-shard-${shard}-19283746-1`)
    fs.mkdirSync(artifactDir, { recursive: true })
    fs.writeFileSync(path.join(artifactDir, 'ctrf-report.json'), JSON.stringify(report))
  }
  return dir
}

const allShards = Array.from({ length: 20 }, (_, index) => index + 1)

const greenRun = (shards = allShards) =>
  Object.fromEntries(
    shards.map((shard) => [shard, ctrfReport([passing(STANDARD_SPEC), passing(REGRESSION_SPEC)])])
  )

const nightlyContext = {
  eventName: 'schedule',
  coreBranch: 'develop',
  coreImageTag: 'develop',
  runUrl: 'https://github.com/opencrvs/opencrvs-testland-infrastructure/actions/runs/1',
  regressionEnabled: true
}

const summarizeDir = (reportsByShard, options = {}) =>
  summarize({
    shardReports: readShardReports(writeReportsDir(reportsByShard)),
    expectedShards: allShards,
    stageResults: {},
    ...options
  })

describe('toSpecPath', () => {
  it('makes an absolute runner path repo-relative', () => {
    assert.equal(toSpecPath(RUNNER_PREFIX + STANDARD_SPEC), STANDARD_SPEC)
  })

  it('leaves an already-relative path alone', () => {
    assert.equal(toSpecPath(STANDARD_SPEC), STANDARD_SPEC)
  })

  it('keeps the full path rather than the basename, so duplicate basenames stay distinct', () => {
    const birth = 'packages/testland/e2e/testcases/birth/1-birth-event-declaration.spec.ts'
    const regression =
      'packages/testland/e2e/testcases/qa-testrail-testcases/birth/1-birth-event-declaration.spec.ts'
    assert.notEqual(toSpecPath(RUNNER_PREFIX + birth), toSpecPath(RUNNER_PREFIX + regression))
  })
})

describe('isRegressionSpec', () => {
  it('classifies by the opt-in suite directory, matching playwright.config.ts testIgnore', () => {
    assert.equal(isRegressionSpec(REGRESSION_SPEC), true)
    assert.equal(isRegressionSpec(STANDARD_SPEC), false)
  })
})

describe('readShardReports', () => {
  it('keys reports by the shard index in the artifact directory name', () => {
    const reports = readShardReports(writeReportsDir({ 3: ctrfReport([passing(STANDARD_SPEC)]) }))
    assert.deepEqual([...reports.keys()], [3])
  })

  it('parses the real reporter output committed as a fixture', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'nightly-notify-real-'))
    const artifactDir = path.join(dir, 'ctrf-e2e-shard-7-19283746-1')
    fs.mkdirSync(artifactDir)
    fs.copyFileSync(
      path.join(here, 'fixtures', 'shard-report.json'),
      path.join(artifactDir, 'ctrf-report.json')
    )

    const summary = summarize({
      shardReports: readShardReports(dir),
      expectedShards: [7],
      stageResults: {}
    })

    assert.equal(summary.outcome, 'failure')
    assert.equal(summary.tests.passed, 2)
    assert.equal(summary.tests.skipped, 1)
    assert.equal(summary.tests.flaky, 1)
    assert.deepEqual(summary.failures.standard, [])
    assert.equal(summary.failures.regression.length, 1)
  })

  it('ignores an artifact directory that is not a ctrf shard', () => {
    const dir = writeReportsDir({ 1: ctrfReport([passing(STANDARD_SPEC)]) })
    fs.mkdirSync(path.join(dir, 'playwright-report-e2e-shard-1-19283746-1'))
    assert.deepEqual([...readShardReports(dir).keys()], [1])
  })
})

describe('summarize: all green', () => {
  it('reports success from 20 clean reports', () => {
    const summary = summarizeDir(greenRun())

    assert.equal(summary.outcome, 'success')
    assert.equal(summary.tests.passed, 40)
    assert.equal(summary.tests.failed, 0)
    assert.deepEqual(summary.missingShards, [])
    assert.deepEqual(summary.failedStages, [])
  })

  it('counts the distinct regression specs that ran', () => {
    assert.equal(summarizeDir(greenRun()).regressionSpecCount, 1)
  })

  it('measures wall-clock across the whole fan-out, not one shard', () => {
    const summary = summarizeDir({
      1: ctrfReport([passing(STANDARD_SPEC)], { start: 1000, durationMs: 5000 }),
      2: ctrfReport([passing(STANDARD_SPEC)], { start: 3000, durationMs: 9000 })
    }, { expectedShards: [1, 2] })

    assert.equal(summary.wallClockMs, 11_000)
  })
})

describe('summarize: failure classification', () => {
  it('splits failures into standard and regression groups', () => {
    const summary = summarizeDir({
      ...greenRun(allShards.slice(2)),
      1: ctrfReport([failing(STANDARD_SPEC, 'declares a birth'), passing(REGRESSION_SPEC)]),
      2: ctrfReport([passing(STANDARD_SPEC), failing(REGRESSION_SPEC, 'community leader birth')])
    })

    assert.equal(summary.outcome, 'failure')
    assert.deepEqual(
      summary.failures.standard.map((failure) => failure.specPath),
      [STANDARD_SPEC]
    )
    assert.deepEqual(
      summary.failures.regression.map((failure) => failure.specPath),
      [REGRESSION_SPEC]
    )
  })

  it('names failing specs by full repo-relative path, never basename', () => {
    const summary = summarizeDir(
      { 1: ctrfReport([failing(STANDARD_SPEC)]) },
      { expectedShards: [1] }
    )
    assert.equal(summary.failures.standard[0].specPath, STANDARD_SPEC)
  })

  it('groups several failing tests in one spec into a single entry', () => {
    const summary = summarizeDir(
      { 1: ctrfReport([failing(STANDARD_SPEC, 'one'), failing(STANDARD_SPEC, 'two')]) },
      { expectedShards: [1] }
    )

    assert.equal(summary.failures.standard.length, 1)
    assert.equal(summary.failures.standard[0].failedTests, 2)
  })

  it('merges the same failing spec across shards', () => {
    const summary = summarizeDir(
      {
        1: ctrfReport([failing(STANDARD_SPEC, 'one')]),
        2: ctrfReport([failing(STANDARD_SPEC, 'two')])
      },
      { expectedShards: [1, 2] }
    )

    assert.equal(summary.failures.standard.length, 1)
    assert.equal(summary.failures.standard[0].failedTests, 2)
  })
})

describe('summarize: missing shard', () => {
  it('names the missing shard index and does not report success', () => {
    const received = allShards.filter((shard) => shard !== 14)
    const summary = summarizeDir(greenRun(received))

    assert.equal(summary.outcome, 'failure')
    assert.deepEqual(summary.missingShards, [14])
  })

  it('reports a missing shard separately from test failures', () => {
    const summary = summarizeDir(greenRun(allShards.filter((shard) => shard !== 14)))

    assert.equal(summary.tests.failed, 0)
    assert.deepEqual(summary.failures.standard, [])
    assert.deepEqual(summary.failures.regression, [])
  })

  it('lists every missing shard in ascending order', () => {
    const summary = summarizeDir(greenRun([1, 2, 3]))
    assert.deepEqual(summary.missingShards, allShards.slice(3))
  })
})

describe('summarize: flaky counting', () => {
  it('counts tests rescued on retry without reporting them as failures', () => {
    const summary = summarizeDir(
      {
        1: ctrfReport([
          { spec: STANDARD_SPEC, status: 'passed', flaky: true },
          { spec: OTHER_STANDARD_SPEC, status: 'passed', flaky: true },
          passing(STANDARD_SPEC)
        ])
      },
      { expectedShards: [1] }
    )

    assert.equal(summary.tests.flaky, 2)
    assert.equal(summary.tests.failed, 0)
    assert.deepEqual(summary.failures.standard, [])
    assert.equal(summary.outcome, 'success')
  })
})

describe('summarize: pipeline stages outside the test fan-out', () => {
  it('fails on a failed upstream stage even with no reports at all', () => {
    const summary = summarize({
      shardReports: new Map(),
      expectedShards: allShards,
      stageResults: { deploy: 'failure', 'reset-data': 'success' }
    })

    assert.equal(summary.outcome, 'failure')
    assert.deepEqual(summary.failedStages, ['deploy'])
    assert.equal(summary.ranTests, false)
  })

  it('does not treat a skipped stage as a failure', () => {
    const summary = summarizeDir(greenRun(), {
      stageResults: { deploy: 'success', test: 'skipped' }
    })
    assert.equal(summary.outcome, 'success')
  })
})

describe('renderSlackMessage: success', () => {
  const message = renderSlackMessage(
    summarizeDir({
      ...greenRun(allShards.slice(1)),
      1: ctrfReport([{ spec: STANDARD_SPEC, status: 'passed', flaky: true }], {
        start: 1_755_043_200_000,
        durationMs: 1_684_000
      })
    }),
    nightlyContext
  )

  it('states that it passed', () => {
    assert.match(message, /^✅ /)
  })

  it('identifies the run as the nightly rather than naming a GitHub actor', () => {
    assert.match(message, /Nightly e2e/)
    assert.doesNotMatch(message, /triggered by/)
  })

  it('carries the passed count, wall-clock, regression spec count and flaky count', () => {
    assert.match(message, /39 passed/)
    assert.match(message, /28m 04s/)
    assert.match(message, /regression: 1 spec/)
    assert.match(message, /1 test rescued on retry/)
  })

  it('links the run', () => {
    assert.match(message, /actions\/runs\/1/)
  })

  it('says nothing about failures or missing shards', () => {
    assert.doesNotMatch(message, /failure/i)
    assert.doesNotMatch(message, /missing|no report/i)
  })
})

describe('renderSlackMessage: failure', () => {
  const summary = summarizeDir({
    ...greenRun(allShards.slice(3)),
    1: ctrfReport([failing(STANDARD_SPEC, 'declares a birth')]),
    2: ctrfReport([failing(REGRESSION_SPEC, 'community leader birth')]),
    3: ctrfReport([failing(OTHER_STANDARD_SPEC, 'declares a death')])
  })
  const message = renderSlackMessage(summary, nightlyContext)

  it('states that it failed', () => {
    assert.match(message, /^❌ /)
  })

  it('splits the two suites into separate labelled groups', () => {
    const regressionAt = message.indexOf('Regression suite')
    const standardAt = message.indexOf('Standard suite')
    assert.ok(regressionAt > -1 && standardAt > -1)
    assert.ok(regressionAt < standardAt, 'regression failures come first — they route to QA')
  })

  it('names each failing spec by full path', () => {
    assert.ok(message.includes(STANDARD_SPEC))
    assert.ok(message.includes(OTHER_STANDARD_SPEC))
    assert.ok(message.includes(REGRESSION_SPEC))
  })

  it('still reports the totals', () => {
    assert.match(message, /3 failed/)
  })
})

describe('renderSlackMessage: missing shard', () => {
  const message = renderSlackMessage(
    summarizeDir(greenRun(allShards.filter((shard) => shard !== 14))),
    nightlyContext
  )

  it('does not read as a pass', () => {
    assert.match(message, /^❌ /)
    assert.doesNotMatch(message, /passed on/)
  })

  it('names the shard that reported nothing', () => {
    assert.match(message, /No report from shard 14\b/)
  })

  it('pluralises when several shards reported nothing', () => {
    const missingTwo = renderSlackMessage(
      summarizeDir(greenRun(allShards.filter((shard) => shard !== 4 && shard !== 14))),
      nightlyContext
    )
    assert.match(missingTwo, /No report from shards 4, 14\b/)
  })

  it('distinguishes a missing report from a test failure', () => {
    assert.match(message, /no report/i)
    assert.doesNotMatch(message, /Standard suite failures/)
  })
})

describe('renderSlackMessage: failed before the tests ran', () => {
  const message = renderSlackMessage(
    summarize({
      shardReports: new Map(),
      expectedShards: allShards,
      stageResults: { deploy: 'failure' }
    }),
    nightlyContext
  )

  it('names the stage that failed instead of listing 20 missing shards', () => {
    assert.match(message, /^❌ /)
    assert.match(message, /deploy/)
    assert.doesNotMatch(message, /shard 14/)
  })
})

describe('renderSlackMessage: manual dispatch', () => {
  it('names the actor who dispatched it', () => {
    const message = renderSlackMessage(summarizeDir(greenRun()), {
      ...nightlyContext,
      eventName: 'workflow_dispatch',
      actor: 'a-developer'
    })

    assert.match(message, /triggered by a-developer/)
    assert.doesNotMatch(message, /Nightly e2e/)
  })

  it('states when the regression suite was opted out of, so a thin run is not misread', () => {
    const message = renderSlackMessage(
      summarizeDir(
        Object.fromEntries(allShards.map((shard) => [shard, ctrfReport([passing(STANDARD_SPEC)])]))
      ),
      { ...nightlyContext, eventName: 'workflow_dispatch', actor: 'a-developer', regressionEnabled: false }
    )

    assert.match(message, /regression: off/)
  })
})

describe('renderSlackMessage: a catastrophic run stays inside Slack limits', () => {
  it('truncates a very long failure list and says how many were dropped', () => {
    const specs = Array.from(
      { length: 80 },
      (_, index) => `packages/testland/e2e/testcases/birth/spec-${index}.spec.ts`
    )
    const message = renderSlackMessage(
      summarizeDir(
        { 1: ctrfReport(specs.map((spec) => failing(spec))) },
        { expectedShards: [1] }
      ),
      nightlyContext
    )

    assert.match(message, /\d+ more/)
    assert.ok(message.length < 4000, `message was ${message.length} characters`)
  })
})

describe('stageResultsFromNeeds', () => {
  it('flattens the `needs` context so the workflow can pass toJSON(needs) verbatim', () => {
    const stages = stageResultsFromNeeds({
      'reset-data': { result: 'success', outputs: {} },
      deploy: { result: 'failure', outputs: {} }
    })

    assert.deepEqual(stages, { 'reset-data': 'success', deploy: 'failure' })
  })

  it('drops the test job, whose failures are reported as failing specs instead', () => {
    const stages = stageResultsFromNeeds({
      deploy: { result: 'success' },
      test: { result: 'failure' }
    })

    assert.deepEqual(stages, { deploy: 'success' })
  })
})

describe('summarize: a test job that failed with nothing to show for it', () => {
  it('fails the run when the test job failed but no spec failed and no shard is missing', () => {
    const summary = summarizeDir(greenRun(), { testJobResult: 'failure' })

    assert.equal(summary.outcome, 'failure')
    assert.equal(summary.unexplainedTestFailure, true)
  })

  it('stays quiet about it when failing specs already explain the failure', () => {
    const summary = summarizeDir(
      { ...greenRun(allShards.slice(1)), 1: ctrfReport([failing(STANDARD_SPEC)]) },
      { testJobResult: 'failure' }
    )

    assert.equal(summary.unexplainedTestFailure, false)
  })

  it('stays quiet about it when a missing shard already explains the failure', () => {
    const summary = summarizeDir(greenRun(allShards.slice(1)), { testJobResult: 'failure' })

    assert.equal(summary.unexplainedTestFailure, false)
    assert.deepEqual(summary.missingShards, [1])
  })

  it('renders a line saying the shards reported no failure, so a green-looking red run is legible', () => {
    const message = renderSlackMessage(
      summarizeDir(greenRun(), { testJobResult: 'failure' }),
      nightlyContext
    )

    assert.match(message, /^❌ /)
    assert.match(message, /no failing test and no missing report/i)
  })
})
