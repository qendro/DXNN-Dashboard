import Chart from "chart.js/auto"

// Performance Chart Hook using Chart.js
export const PerformanceChart = {
  mounted() {
    this.canvas = this.el.querySelector("canvas")
    this.initChart()
  },
  
  updated() {
    this.updateChart()
  },
  
  initChart() {
    const chartConfig = this.readConfig()
    if (!chartConfig || !this.canvas) {
      return
    }

    const ctx = this.canvas.getContext('2d')

    if (!ctx) {
      return
    }

    this.chart = new Chart(ctx, {
      type: 'line',
      data: {
        datasets: [{
          label: chartConfig.label,
          data: chartConfig.data,
          borderColor: 'rgb(59, 130, 246)',
          backgroundColor: 'rgba(59, 130, 246, 0.1)',
          borderWidth: 2,
          pointRadius: 2,
          pointHoverRadius: 4,
          tension: 0.1
        }]
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: {
            type: 'linear',
            title: {
              display: true,
              text: 'Evaluation #'
            }
          },
          y: {
            title: {
              display: true,
              text: chartConfig.label
            }
          }
        },
        plugins: {
          legend: {
            display: true,
            position: 'top'
          },
          tooltip: {
            mode: 'index',
            intersect: false
          }
        },
        interaction: {
          mode: 'nearest',
          axis: 'x',
          intersect: false
        }
      }
    })
  },
  
  updateChart() {
    if (!this.chart) {
      this.initChart()
      return
    }

    const chartConfig = this.readConfig()
    if (!chartConfig) {
      return
    }
    
    this.chart.data.datasets[0].data = chartConfig.data
    this.chart.data.datasets[0].label = chartConfig.label
    this.chart.options.scales.y.title.text = chartConfig.label
    this.chart.update()
    this.chart.resize()
  },

  readConfig() {
    try {
      return JSON.parse(this.el.dataset.chart || "{}")
    } catch (_error) {
      return null
    }
  },
  
  destroyed() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}
