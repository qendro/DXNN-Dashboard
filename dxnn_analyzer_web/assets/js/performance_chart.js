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

    // Handle both old format (array) and new format (object with raw/sma)
    const rawData = chartConfig.data.raw || chartConfig.data
    const smaData = chartConfig.data.sma || []

    console.log('=== CHART INIT DEBUG ===')
    console.log('chartConfig.data:', chartConfig.data)
    console.log('rawData length:', rawData.length)
    console.log('smaData length:', smaData.length)
    console.log('First 3 raw points:', rawData.slice(0, 3))
    console.log('First 3 SMA points:', smaData.slice(0, 3))
    console.log('Last 3 SMA points:', smaData.slice(-3))

    this.chart = new Chart(ctx, {
      type: 'line',
      data: {
        datasets: [
        {
          label: '200-Point SMA',
          data: smaData,
          borderColor: 'rgb(239, 68, 68)',
          backgroundColor: 'rgba(239, 68, 68, 0)',
          borderWidth: 3,
          pointRadius: 0,
          pointHoverRadius: 0,
          tension: 0.4,
          spanGaps: true,
          order: 1
        },
        {
          label: chartConfig.label,
          data: rawData,
          borderColor: 'rgb(59, 130, 246)',
          backgroundColor: 'rgba(59, 130, 246, 0)',
          borderWidth: 1.5,
          pointRadius: 0,
          pointHoverRadius: 0,
          tension: 0.1,
          order: 2
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
    
    // Handle both old format (array) and new format (object with raw/sma)
    const rawData = chartConfig.data.raw || chartConfig.data
    const smaData = chartConfig.data.sma || []

    console.log('Updating chart data:', { rawData: rawData.length, smaData: smaData.length })
    
    // Dataset 0 is SMA, Dataset 1 is raw data
    this.chart.data.datasets[0].data = smaData
    this.chart.data.datasets[1].data = rawData
    this.chart.data.datasets[1].label = chartConfig.label
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
