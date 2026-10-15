import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const source = readFileSync(new URL("./instance_time.js", import.meta.url), "utf8")
const { formatLaunchTime, timeSinceLaunch } = await import(
  "data:text/javascript;base64," + Buffer.from(source).toString("base64")
)

assert.match(formatLaunchTime("2026-10-11T22:00:00Z"), /Oct 11, 2026.*5:00 PM CDT/)
assert.match(formatLaunchTime("2026-01-11T22:00:00Z"), /Jan 11, 2026.*4:00 PM CST/)
assert.equal(timeSinceLaunch("2026-10-11T22:00:00Z", Date.parse("2026-10-14T01:04:00Z")), "2d 3h")
assert.equal(timeSinceLaunch("2026-10-11T22:00:00Z", Date.parse("2026-10-11T23:04:00Z")), "1h 4m")
assert.equal(timeSinceLaunch("2026-10-11T22:00:00Z", Date.parse("2026-10-11T22:00:30Z")), "Less than a minute")
assert.equal(timeSinceLaunch("invalid"), "—")
assert.equal(timeSinceLaunch("2026-10-12T22:00:00Z", Date.parse("2026-10-11T22:00:00Z")), "—")
assert.equal(formatLaunchTime(null), "—")
console.log("Instance launch time and elapsed time checks passed")
