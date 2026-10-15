const launchFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/Chicago",
  month: "short", day: "numeric", year: "numeric",
  hour: "numeric", minute: "2-digit", timeZoneName: "short"
})

export function formatLaunchTime(value) {
  const milliseconds = Date.parse(value || "")
  return Number.isFinite(milliseconds) ? launchFormatter.format(milliseconds) : "—"
}

export function timeSinceLaunch(value, now = Date.now()) {
  const milliseconds = Date.parse(value || "")
  if (!Number.isFinite(milliseconds) || milliseconds > now) return "—"
  const minutes = Math.floor((now - milliseconds) / 60000)
  const hours = Math.floor(minutes / 60)
  const days = Math.floor(hours / 24)
  if (days) return `${days}d ${hours % 24}h`
  if (hours) return `${hours}h ${minutes % 60}m`
  return minutes ? `${minutes}m` : "Less than a minute"
}

export const InstanceTime = {
  mounted() {
    this.updateTime()
    this.timer = setInterval(() => this.updateTime(), 60000)
  },
  updated() { this.updateTime() },
  destroyed() { clearInterval(this.timer) },
  updateTime() {
    const launched = this.el.dataset.launchedAt
    this.el.querySelector("[data-launch-time]").textContent = formatLaunchTime(launched)
    this.el.querySelector("[data-elapsed-time]").textContent = timeSinceLaunch(launched)
  }
}
