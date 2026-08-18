import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))

/** Runs the CLI the way the notify job does, and returns stdout plus the
 * step outputs it wrote. */
function runCli({ shards, env = {} }) {
  const workDir = fs.mkdtempSync(path.join(os.tmpdir(), 'nightly-notify-cli-'))
  const reportsDir = path.join(workDir, 'reports')

  for (const shard of shards) {
    const artifactDir = path.join(reportsDir, `ctrf-e2e-shard-${shard}-19283746-1`)
    fs.mkdirSync(artifactDir, { recursive: true })
    fs.copyFileSync(
      path.join(here, 'fixtures', 'shard-report.json'),
      path.join(artifactDir, 'ctrf-report.json')
    )
  }

  const outputFile = path.join(workDir, 'github-output')
  fs.writeFileSync(outputFile, '')

  const stdout = execFileSync(process.execPath, [path.join(here, 'main.mjs'), reportsDir], {
    encoding: 'utf8',
    env: {
      EXPECTED_SHARDS: JSON.stringify(shards),
      EVENT_NAME: 'schedule',
      CORE_BRANCH: 'develop',
      CORE_IMAGE_TAG: 'develop',
      RUN_URL: 'https://github.com/opencrvs/opencrvs-testland-infrastructure/actions/runs/1',
      REGRESSION_ENABLED: 'true',
      GITHUB_OUTPUT: outputFile,
      ...env
    }
  })

  return { stdout, outputs: fs.readFileSync(outputFile, 'utf8') }
}

describe('main.mjs', () => {
  it('prints the message and writes it as a step output', () => {
    const { stdout, outputs } = runCli({ shards: [7] })

    assert.match(stdout, /^❌ Nightly e2e failed/)
    assert.match(outputs, /^outcome=failure$/m)
    assert.match(outputs, /Nightly e2e failed/)
  })

  it('quotes the multi-line message so a spec path cannot forge a step output', () => {
    const { outputs } = runCli({ shards: [7] })
    assert.match(outputs, /message<<ghadelimiter_[0-9a-f-]{36}\n/)
  })

  it('reports a stage that failed before any artifact existed', () => {
    const { stdout, outputs } = runCli({
      shards: [],
      env: {
        EXPECTED_SHARDS: '[1,2,3]',
        NEEDS: '{"deploy":{"result":"failure"},"test":{"result":"skipped"}}'
      }
    })

    assert.match(stdout, /failed outside the test suite: deploy/)
    assert.match(outputs, /^outcome=failure$/m)
  })
})

describe('main.mjs: the test job failed but the reports are clean', () => {
  it('does not report success', () => {
    const { stdout, outputs } = runCli({
      shards: [7],
      env: { TEST_JOB_RESULT: 'failure' }
    })

    assert.match(stdout, /^❌ /)
    assert.match(outputs, /^outcome=failure$/m)
  })
})
