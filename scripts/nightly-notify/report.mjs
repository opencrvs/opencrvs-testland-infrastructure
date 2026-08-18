/**
 * Merges the per-shard CTRF reports of one "Deploy & run E2E" run into a single
 * Slack message.
 *
 * Kept out of the workflow YAML on purpose: the merge, the suite split and the
 * missing-shard check are the only real logic in the nightly, and their most
 * important paths (a shard that never reported, a failure in each suite) are
 * ones a healthy run never produces. Run them against the fixtures instead:
 *
 *   yarn test        # node --test "scripts/nightly-notify/*.test.mjs"
 */
import fs from 'node:fs'
import path from 'node:path'

/**
 * The opt-in suite directory from the `optInSuites` array in core's
 * `packages/testland/playwright.config.ts`, which is where Playwright decides
 * whether these specs run at all.
 *
 * This is a second copy of that value, in a second repository, and nothing
 * enforces the pair. If they drift, the regression specs still run correctly —
 * only the Slack message misfiles them, putting a regression failure in the
 * standard group. The tests below pin the classification; the coupling is the
 * reason the suite split is asserted rather than assumed.
 */
const REGRESSION_SEGMENT = 'testcases/qa-testrail-testcases/'

/** Where a spec path becomes repo-relative: everything left of it is the runner's workspace. */
const REPO_ROOT_SEGMENT = 'packages/testland/'

/** The artifact name the test job uploads, which is where the shard index comes from. */
const SHARD_ARTIFACT_PATTERN = /^ctrf-e2e-shard-(\d+)(?:-|$)/

const UNKNOWN_SPEC =
  '(unknown spec — the CTRF reporter is in minimal mode and recorded no file paths)'

/** Failing specs beyond this are summarised as a count: `chat.postMessage` caps text at 40k. */
const MAX_LISTED_SPECS_PER_SUITE = 15

/** A GitHub job conclusion that means the stage did not do its job. */
const FAILED_CONCLUSIONS = new Set(['failure', 'cancelled', 'timed_out'])

/**
 * Turns the absolute path the CTRF reporter records (`testCase.location.file`,
 * rooted in the runner's workspace) into the repo-relative path a triager can
 * paste into an editor.
 *
 * Full paths rather than basenames throughout: 8 basenames are duplicated on
 * develop today, and the standard and regression birth-declaration specs differ
 * by a single character.
 */
export function toSpecPath(filePath) {
  // The reporter only records filePath when its `minimal` option is false. That
  // is the default, but the default lives in core's playwright.config.ts — so
  // say why the paths went missing rather than throwing and sending no message
  // at all.
  if (typeof filePath !== 'string') return UNKNOWN_SPEC

  const normalised = filePath.split(path.sep).join('/')
  const rootAt = normalised.lastIndexOf(REPO_ROOT_SEGMENT)
  return rootAt === -1 ? normalised : normalised.slice(rootAt)
}

export function isRegressionSpec(specPath) {
  return specPath.includes(REGRESSION_SEGMENT)
}

/**
 * Reads a directory of downloaded artifacts, keyed by the shard index in each
 * artifact's name.
 *
 * The index comes from the artifact name rather than from a count, so the
 * caller can compare against the shard matrix and name *which* shard is missing.
 */
export function readShardReports(reportsDir) {
  const reports = new Map()

  for (const entry of fs.readdirSync(reportsDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue

    const shardMatch = SHARD_ARTIFACT_PATTERN.exec(entry.name)
    if (shardMatch === null) continue

    const artifactDir = path.join(reportsDir, entry.name)
    const reportFile = fs
      .readdirSync(artifactDir)
      .find((file) => file.endsWith('.json'))

    if (reportFile === undefined) continue

    reports.set(
      Number(shardMatch[1]),
      JSON.parse(fs.readFileSync(path.join(artifactDir, reportFile), 'utf8'))
    )
  }

  return reports
}

/**
 * Flattens GitHub's `needs` context into stage -> conclusion, so the workflow
 * can pass `toJSON(needs)` and never restate its own `needs:` list.
 *
 * `test` is dropped: it fails whenever a shard fails, which the failing-spec
 * groups already say better.
 */
export function stageResultsFromNeeds(needs) {
  return Object.fromEntries(
    Object.entries(needs)
      .filter(([stage]) => stage !== 'test')
      .map(([stage, { result }]) => [stage, result])
  )
}

/**
 * @param shardReports  shard index -> CTRF report, from `readShardReports`
 * @param expectedShards  the shard matrix, so a shard that reported nothing is named
 * @param stageResults  job name -> GitHub conclusion, for the stages around the fan-out
 * @param testJobResult  the test job's own conclusion, to catch a shard that
 *   failed without producing a failing test — a Playwright config error, or the
 *   zero-matched-tests exit a shard packed only with excluded specs gives
 */
export function summarize({
  shardReports,
  expectedShards,
  stageResults = {},
  testJobResult = 'success'
}) {
  const tests = { total: 0, passed: 0, failed: 0, skipped: 0, flaky: 0 }
  const failuresBySpec = new Map()
  const regressionSpecs = new Set()
  let start = Infinity
  let stop = 0

  for (const report of shardReports.values()) {
    const results = report.results
    // Milliseconds here, unlike the per-test start/stop the same reporter
    // writes in seconds.
    start = Math.min(start, results.summary.start)
    stop = Math.max(stop, results.summary.stop)

    // Counted from the tests array rather than the summary block: the reporter
    // records one entry per test carrying its *final* attempt, so a test
    // rescued on retry appears once, as passed and flaky.
    for (const test of results.tests) {
      const specPath = toSpecPath(test.filePath)
      tests.total += 1
      if (test.flaky === true) tests.flaky += 1
      if (isRegressionSpec(specPath)) regressionSpecs.add(specPath)

      if (test.status === 'passed') tests.passed += 1
      else if (test.status === 'skipped') tests.skipped += 1
      else if (test.status === 'failed') {
        tests.failed += 1
        const failure = failuresBySpec.get(specPath) ?? {
          specPath,
          failedTests: 0,
          testNames: []
        }
        failure.failedTests += 1
        failure.testNames.push(test.name)
        failuresBySpec.set(specPath, failure)
      }
    }
  }

  const failures = [...failuresBySpec.values()].sort((a, b) =>
    a.specPath.localeCompare(b.specPath)
  )
  const missingShards = expectedShards
    .filter((shard) => !shardReports.has(shard))
    .sort((a, b) => a - b)
  const failedStages = Object.entries(stageResults)
    .filter(([, conclusion]) => FAILED_CONCLUSIONS.has(conclusion))
    .map(([stage]) => stage)
    .sort()

  // A shard job can fail with nothing in its report to show for it. Only worth
  // saying when neither a failing spec nor a missing report already explains
  // the red, otherwise every ordinary failure carries a redundant line.
  const unexplainedTestFailure =
    FAILED_CONCLUSIONS.has(testJobResult) &&
    tests.failed === 0 &&
    missingShards.length === 0

  return {
    // A partial run must never read as green, and the shard set — not the job
    // timeout — is what guarantees it: a shard killed mid-suite writes no CTRF
    // at all, so it merges one report fewer and its failures vanish.
    outcome:
      tests.failed > 0 ||
      missingShards.length > 0 ||
      failedStages.length > 0 ||
      unexplainedTestFailure
        ? 'failure'
        : 'success',
    ranTests: shardReports.size > 0,
    unexplainedTestFailure,
    tests,
    failures: {
      regression: failures.filter((failure) => isRegressionSpec(failure.specPath)),
      standard: failures.filter((failure) => !isRegressionSpec(failure.specPath))
    },
    regressionSpecCount: regressionSpecs.size,
    missingShards,
    expectedShardCount: expectedShards.length,
    failedStages,
    // Wall-clock of the whole fan-out, not of the longest shard.
    wallClockMs: shardReports.size === 0 ? 0 : stop - start
  }
}

function formatDuration(milliseconds) {
  const totalSeconds = Math.round(milliseconds / 1000)
  const seconds = String(totalSeconds % 60).padStart(2, '0')
  const minutes = Math.floor(totalSeconds / 60) % 60
  const hours = Math.floor(totalSeconds / 3600)

  return hours > 0
    ? `${hours}h ${String(minutes).padStart(2, '0')}m ${seconds}s`
    : `${minutes}m ${seconds}s`
}

const pluralise = (count, noun) => `${count} ${noun}${count === 1 ? '' : 's'}`

function formatRegression(regressionEnabled, regressionSpecCount) {
  // "regression: 0 specs" is deliberately reported rather than hidden: it is
  // the line that reveals a regression suite that silently stopped being
  // collected.
  return regressionEnabled
    ? `regression: ${pluralise(regressionSpecCount, 'spec')}`
    : 'regression: off'
}

function formatSuiteFailures(label, failures) {
  if (failures.length === 0) return []

  const listed = failures.slice(0, MAX_LISTED_SPECS_PER_SUITE)
  const lines = [
    '',
    `*${label} failures (${pluralise(failures.length, 'spec')})*`,
    ...listed.map(
      ({ specPath, failedTests, testNames }) =>
        `• \`${specPath}\` — ${
          failedTests === 1 ? testNames[0] : `${failedTests} tests`
        }`
    )
  ]

  if (failures.length > listed.length) {
    lines.push(`• …and ${failures.length - listed.length} more specs`)
  }

  return lines
}

/**
 * @param context  { eventName, actor, coreBranch, coreImageTag, runUrl, regressionEnabled }
 */
export function renderSlackMessage(summary, context) {
  // On a `schedule:` trigger there is no client payload and `github.actor` names
  // nobody useful, so the nightly identifies itself instead of naming a human.
  const runLabel =
    context.eventName === 'schedule'
      ? 'Nightly e2e'
      : `E2E triggered by ${context.actor}`
  const target =
    context.coreImageTag && context.coreImageTag !== context.coreBranch
      ? `\`${context.coreBranch}\` (core: \`${context.coreImageTag}\`)`
      : `\`${context.coreBranch}\``

  const passed = summary.outcome === 'success'
  const counts = [
    passed
      ? `${summary.tests.passed} passed`
      : `${summary.tests.passed} passed, ${summary.tests.failed} failed`,
    ...(summary.tests.skipped > 0 ? [`${summary.tests.skipped} skipped`] : []),
    formatDuration(summary.wallClockMs),
    formatRegression(context.regressionEnabled, summary.regressionSpecCount),
    `${pluralise(summary.tests.flaky, 'test')} rescued on retry`
  ]

  const lines = [
    `${passed ? '✅' : '❌'} ${runLabel} ${passed ? 'passed' : 'failed'} on ${target}`
  ]

  if (summary.ranTests) lines.push(counts.join(' · '))

  if (summary.failedStages.length > 0) {
    lines.push(
      '',
      `⚠️ The run failed outside the test suite: ${summary.failedStages.join(', ')}`
    )
  } else if (!summary.ranTests) {
    lines.push(
      '',
      `⚠️ No report from any of the ${summary.expectedShardCount} shards.`
    )
  } else if (summary.missingShards.length > 0) {
    // Reported apart from test failures: a shard that hit the job timeout or
    // crashed has no results at all, so the totals above are short by however
    // much it was carrying.
    lines.push(
      '',
      `⚠️ No report from shard${summary.missingShards.length === 1 ? '' : 's'} ${summary.missingShards.join(', ')} — timed out or crashed, so the counts above are incomplete.`
    )
  }

  if (summary.unexplainedTestFailure && summary.ranTests) {
    lines.push(
      '',
      '⚠️ A shard job failed with no failing test and no missing report — check the shard logs for a Playwright or config error.'
    )
  }

  // Regression first: a `qa-testrail-testcases/` failure is QA's call between a
  // test-case update and a product bug, and anything else is a dev regression,
  // so the split routes the message before anyone opens the run.
  lines.push(
    ...formatSuiteFailures('Regression suite', summary.failures.regression),
    ...formatSuiteFailures('Standard suite', summary.failures.standard)
  )

  lines.push('', `<${context.runUrl}|View run>`)

  return lines.join('\n')
}
