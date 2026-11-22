// Network Graph Visualization using D3.js
import * as d3 from "d3";

export const NetworkGraph = {
  mounted() {
    this.initGraph();
    this.renderGraph();
  },

  updated() {
    // Only re-render if layout or graph data changed, not on selection changes
    const newLayout = this.el.dataset.layout;
    const newGraph = this.el.dataset.graph;
    
    if (this.currentLayout !== newLayout || this.currentGraph !== newGraph) {
      this.currentLayout = newLayout;
      this.currentGraph = newGraph;
      this.renderGraph();
    }
  },

  initGraph() {
    const container = this.el;
    const svg = d3.select(container).select("svg");
    
    // Clear any existing content
    svg.selectAll("*").remove();
    
    // Create main group for zoom/pan
    this.mainGroup = svg.append("g");
    
    // Add zoom behavior
    const zoom = d3.zoom()
      .scaleExtent([0.1, 4])
      .on("zoom", (event) => {
        this.mainGroup.attr("transform", event.transform);
      });
    
    svg.call(zoom);
    
    // Create groups for edges and nodes
    this.edgeGroup = this.mainGroup.append("g").attr("class", "edges");
    this.nodeGroup = this.mainGroup.append("g").attr("class", "nodes");
    
    this.currentLayout = this.el.dataset.layout;
    this.currentGraph = this.el.dataset.graph;
  },

  renderGraph() {
    const graphData = JSON.parse(this.el.dataset.graph);
    const layout = this.el.dataset.layout || "hierarchical";
    
    if (!graphData || !graphData.nodes || !graphData.edges) {
      console.error("Invalid graph data");
      return;
    }

    const container = this.el;
    const width = container.clientWidth;
    const height = container.clientHeight;

    // Prepare data - store nodes for edge lookup
    this.nodes = graphData.nodes.map(d => ({...d}));
    this.edges = graphData.edges.map(d => ({...d}));
    
    // Create node lookup map
    this.nodeMap = new Map();
    this.nodes.forEach(node => {
      this.nodeMap.set(node.id, node);
    });

    // Apply layout
    if (layout === "hierarchical") {
      this.applyHierarchicalLayout(this.nodes, this.edges, width, height);
    } else if (layout === "force") {
      this.applyForceLayout(this.nodes, this.edges, width, height);
    } else if (layout === "circular") {
      this.applyCircularLayout(this.nodes, this.edges, width, height);
    }

    // Render edges first (so they appear behind nodes)
    this.renderEdges(this.edges, this.nodes);
    
    // Render nodes
    this.renderNodes(this.nodes);
  },

  applyHierarchicalLayout(nodes, edges, width, height) {
    // Separate nodes by type
    const sensors = nodes.filter(n => n.type === "sensor");
    const neurons = nodes.filter(n => n.type === "neuron");
    const actuators = nodes.filter(n => n.type === "actuator");
    
    // Define section widths
    const sensorWidth = 120;
    const actuatorWidth = 120;
    const neuronWidth = width - sensorWidth - actuatorWidth;
    
    const padding = 40;
    
    // Layout sensors in left column (vertically centered)
    const sensorSpacing = Math.min(80, (height - 2 * padding) / Math.max(sensors.length, 1));
    const totalSensorHeight = sensors.length * sensorSpacing;
    const sensorStartY = (height - totalSensorHeight) / 2;
    
    sensors.forEach((node, i) => {
      node.x = sensorWidth / 2;
      node.y = sensorStartY + i * sensorSpacing + sensorSpacing / 2;
    });
    
    // Layout neurons in middle grid with offset rows and columns (brick pattern)
    if (neurons.length > 0) {
      // Calculate grid dimensions
      const aspectRatio = neuronWidth / height;
      let cols = Math.ceil(Math.sqrt(neurons.length * aspectRatio));
      let rows = Math.ceil(neurons.length / cols);
      
      // Adjust for better spacing
      const cellWidth = (neuronWidth - 2 * padding) / cols;
      const cellHeight = (height - 2 * padding) / rows;
      
      neurons.forEach((node, i) => {
        const col = i % cols;
        const row = Math.floor(i / cols);
        
        // Offset every other row horizontally by half a cell width
        const offsetX = (row % 2) * (cellWidth / 2);
        
        // Offset every other column vertically by half a cell height
        const offsetY = (col % 2) * (cellHeight / 2);
        
        node.x = sensorWidth + padding + col * cellWidth + cellWidth / 2 + offsetX;
        node.y = padding + row * cellHeight + cellHeight / 2 + offsetY;
      });
    }
    
    // Layout actuators in right column (vertically centered)
    const actuatorSpacing = Math.min(80, (height - 2 * padding) / Math.max(actuators.length, 1));
    const totalActuatorHeight = actuators.length * actuatorSpacing;
    const actuatorStartY = (height - totalActuatorHeight) / 2;
    
    actuators.forEach((node, i) => {
      node.x = width - actuatorWidth / 2;
      node.y = actuatorStartY + i * actuatorSpacing + actuatorSpacing / 2;
    });
  },

  applyForceLayout(nodes, edges, width, height) {
    // Separate nodes by type for positioning constraints
    const sensors = nodes.filter(n => n.type === "sensor");
    const neurons = nodes.filter(n => n.type === "neuron");
    const actuators = nodes.filter(n => n.type === "actuator");
    
    const sensorWidth = 120;
    const actuatorWidth = 120;
    
    // Initialize positions with constraints
    sensors.forEach((node, i) => {
      node.x = sensorWidth / 2;
      node.y = height / 2 + (i - sensors.length / 2) * 60;
      node.fx = sensorWidth / 2; // Fix x position
    });
    
    actuators.forEach((node, i) => {
      node.x = width - actuatorWidth / 2;
      node.y = height / 2 + (i - actuators.length / 2) * 60;
      node.fx = width - actuatorWidth / 2; // Fix x position
    });
    
    neurons.forEach(node => {
      node.x = width / 2 + (Math.random() - 0.5) * 200;
      node.y = height / 2 + (Math.random() - 0.5) * 200;
    });

    // Create force simulation with better parameters
    const simulation = d3.forceSimulation(nodes)
      .force("link", d3.forceLink(edges)
        .id(d => d.id)
        .distance(d => {
          // Shorter distances for connected nodes
          const sourceNode = this.nodeMap.get(d.source.id || d.source);
          const targetNode = this.nodeMap.get(d.target.id || d.target);
          if (sourceNode && targetNode) {
            if (sourceNode.type === "sensor" || targetNode.type === "actuator") {
              return 150;
            }
          }
          return 100;
        })
        .strength(1))
      .force("charge", d3.forceManyBody()
        .strength(d => d.type === "neuron" ? -200 : -100))
      .force("center", d3.forceCenter(width / 2, height / 2))
      .force("collision", d3.forceCollide()
        .radius(d => d.type === "neuron" ? 25 : 35))
      .force("x", d3.forceX(d => {
        if (d.type === "sensor") return sensorWidth / 2;
        if (d.type === "actuator") return width - actuatorWidth / 2;
        return width / 2;
      }).strength(d => d.type === "neuron" ? 0.1 : 1))
      .force("y", d3.forceY(height / 2).strength(0.1));

    // Run simulation synchronously for initial layout
    simulation.tick(400);
    simulation.stop();
    
    // Clean up fixed positions for neurons (keep sensors/actuators fixed)
    neurons.forEach(node => {
      delete node.fx;
      delete node.fy;
    });
  },

  applyCircularLayout(nodes, edges, width, height) {
    const radius = Math.min(width, height) / 2 - 50;
    const centerX = width / 2;
    const centerY = height / 2;
    
    nodes.forEach((node, i) => {
      const angle = (2 * Math.PI * i) / nodes.length;
      node.x = centerX + radius * Math.cos(angle);
      node.y = centerY + radius * Math.sin(angle);
    });
  },

  renderEdges(edges, nodes) {
    // Use paths instead of lines for better visual control
    const edgeSelection = this.edgeGroup
      .selectAll("path")
      .data(edges, d => `${d.source.id || d.source}-${d.target.id || d.target}`);

    // Remove old edges
    edgeSelection.exit().remove();

    // Add new edges
    const edgeEnter = edgeSelection.enter()
      .append("path")
      .attr("fill", "none")
      .attr("stroke", "#94a3b8")  // All gray
      .attr("stroke-opacity", 0.4)
      .attr("stroke-width", 1.5)
      .attr("stroke-dasharray", d => {
        // Only self-loops (same source and target) are dashed
        const sourceId = d.source.id || d.source;
        const targetId = d.target.id || d.target;
        return sourceId === targetId ? "5,5" : "none";
      })
      .attr("marker-end", "url(#arrowhead)")
      .attr("cursor", "pointer")
      .on("click", (event, d) => {
        event.stopPropagation();
        const sourceId = d.source.id || d.source;
        const targetId = d.target.id || d.target;

        
        // Highlight this edge and connected nodes
        this.highlightEdge(sourceId, targetId);
        
        this.pushEvent("select_edge", { 
          source: sourceId,
          target: targetId,
          weight: d.weight || 0,
          recurrent: d.recurrent || false
        });
      })
      .on("mouseenter", function(event, d) {
        const element = d3.select(this);
        // Don't apply hover effect if already highlighted
        if (element.attr("stroke") === "#f59e0b") return;
        
        element
          .attr("stroke", "#3b82f6")
          .attr("stroke-opacity", 0.8);
      })
      .on("mouseleave", function(event, d) {
        const element = d3.select(this);
        // Don't reset if highlighted
        if (element.attr("stroke") === "#f59e0b") return;
        
        element
          .attr("stroke", "#94a3b8")
          .attr("stroke-opacity", 0.4);
      });

    // Add arrowhead marker
    const defs = this.mainGroup.select("defs").empty() 
      ? this.mainGroup.insert("defs", ":first-child")
      : this.mainGroup.select("defs");
    
    if (defs.select("#arrowhead").empty()) {
      defs.append("marker")
        .attr("id", "arrowhead")
        .attr("viewBox", "0 -5 10 10")
        .attr("refX", 20)
        .attr("refY", 0)
        .attr("markerWidth", 6)
        .attr("markerHeight", 6)
        .attr("orient", "auto")
        .append("path")
        .attr("d", "M0,-5L10,0L0,5")
        .attr("fill", "#94a3b8");
    }

    // Update all edges
    const edgeUpdate = edgeSelection.merge(edgeEnter);
    
    edgeUpdate
      .attr("d", d => {
        const source = this.nodeMap.get(d.source.id || d.source);
        const target = this.nodeMap.get(d.target.id || d.target);
        
        if (!source || !target) return "";
        
        // Self-loop: create a circular arc above the node
        if (source.id === target.id) {
          const loopSize = 30;
          return `M${source.x},${source.y - 10} 
                  C${source.x - loopSize},${source.y - loopSize * 2} 
                  ${source.x + loopSize},${source.y - loopSize * 2} 
                  ${source.x},${source.y - 10}`;
        } else {
          // All other connections: curved path with offset for visibility
          const dx = target.x - source.x;
          const dy = target.y - source.y;
          const dr = Math.sqrt(dx * dx + dy * dy);
          
          // Create a curved path with perpendicular offset
          const midX = (source.x + target.x) / 2;
          const midY = (source.y + target.y) / 2;
          
          // Add slight perpendicular offset to make curve visible
          const offsetX = -dy / dr * 20;  // Perpendicular offset
          const offsetY = dx / dr * 20;
          
          return `M${source.x},${source.y} Q${midX + offsetX},${midY + offsetY} ${target.x},${target.y}`;
        }
      });
  },

  renderNodes(nodes) {
    const nodeSelection = this.nodeGroup
      .selectAll("g")
      .data(nodes, d => d.id);

    // Remove old nodes
    nodeSelection.exit().remove();

    // Add new nodes
    const nodeEnter = nodeSelection.enter()
      .append("g")
      .attr("cursor", "pointer")
      .on("click", (event, d) => {
        event.stopPropagation();
        
        // Highlight connected edges
        this.highlightConnections(d.id);
        
        this.pushEvent("select_node", { node_id: d.id });
      });

    // Add shapes (rectangles for sensors/actuators, circles for neurons)
    nodeEnter.each(function(d) {
      const node = d3.select(this);
      
      if (d.type === "sensor" || d.type === "actuator") {
        // Rectangle for sensors and actuators
        node.append("rect")
          .attr("width", 40)
          .attr("height", 30)
          .attr("x", -20)
          .attr("y", -15)
          .attr("rx", 4)
          .attr("fill", d.type === "sensor" ? "#3b82f6" : "#a855f7")
          .attr("stroke", "#fff")
          .attr("stroke-width", 2);
      } else {
        // Circle for neurons
        node.append("circle")
          .attr("r", 10)
          .attr("fill", "#10b981")
          .attr("stroke", "#fff")
          .attr("stroke-width", 2);
      }
    });

    // Add labels
    nodeEnter.each(function(d) {
      const node = d3.select(this);
      
      if (d.type === "sensor" || d.type === "actuator") {
        // Multi-line label for sensors/actuators (inside the box)
        const lines = d.label.split(' ');
        const text = node.append("text")
          .attr("text-anchor", "middle")
          .attr("font-size", "9px")
          .attr("fill", "#ffffff")  // White text
          .attr("pointer-events", "none");
        
        // First line (name)
        text.append("tspan")
          .attr("x", 0)
          .attr("dy", -5)
          .text(lines[0]);
        
        // Second line (vector length)
        if (lines[1]) {
          text.append("tspan")
            .attr("x", 0)
            .attr("dy", 10)
            .text(lines[1]);
        }
        
        // Add short ID below the box
        node.append("text")
          .attr("dy", 25)
          .attr("text-anchor", "middle")
          .attr("font-size", "9px")
          .attr("fill", "#374151")
          .attr("pointer-events", "none")
          .text(d.short_id);
      } else {
        // Single line label for neurons (below the circle)
        node.append("text")
          .attr("dy", 25)
          .attr("text-anchor", "middle")
          .attr("font-size", "10px")
          .attr("fill", "#374151")
          .attr("pointer-events", "none")
          .text(d.label);
      }
    });

    // Update all nodes
    const nodeUpdate = nodeSelection.merge(nodeEnter);
    
    nodeUpdate.attr("transform", d => `translate(${d.x},${d.y})`);

    // Add hover effects
    nodeUpdate.selectAll("circle, rect")
      .on("mouseenter", function(event, d) {
        const element = d3.select(this);
        // Don't apply hover effect if already highlighted
        if (element.attr("stroke") === "#f59e0b") return;
        
        if (d.type === "sensor" || d.type === "actuator") {
          element
            .transition()
            .duration(200)
            .attr("width", 48)
            .attr("height", 36)
            .attr("x", -24)
            .attr("y", -18);
        } else {
          element
            .transition()
            .duration(200)
            .attr("r", 13);
        }
      })
      .on("mouseleave", function(event, d) {
        const element = d3.select(this);
        // Don't reset if highlighted
        if (element.attr("stroke") === "#f59e0b") return;
        
        if (d.type === "sensor" || d.type === "actuator") {
          element
            .transition()
            .duration(200)
            .attr("width", 40)
            .attr("height", 30)
            .attr("x", -20)
            .attr("y", -15);
        } else {
          element
            .transition()
            .duration(200)
            .attr("r", 10);
        }
      });
  },

  highlightConnections(nodeId) {
    // Reset all edges to default style
    this.edgeGroup.selectAll("path")
      .attr("stroke", d => {
        const sourceId = d.source.id || d.source;
        const targetId = d.target.id || d.target;
        return sourceId === targetId ? "#94a3b8" : "#94a3b8";
      })
      .attr("stroke-opacity", 0.4)
      .attr("stroke-width", 1.5);
    
    // Reset all nodes to default style
    this.nodeGroup.selectAll("circle, rect")
      .attr("stroke", "#fff")
      .attr("stroke-width", 2);
    
    // Highlight edges connected to this node
    this.edgeGroup.selectAll("path")
      .filter(d => {
        const sourceId = d.source.id || d.source;
        const targetId = d.target.id || d.target;
        return sourceId === nodeId || targetId === nodeId;
      })
      .attr("stroke", "#f59e0b")  // Orange for highlighted
      .attr("stroke-opacity", 0.9)
      .attr("stroke-width", 3);
    
    // Highlight the clicked node
    this.nodeGroup.selectAll("g")
      .filter(d => d.id === nodeId)
      .selectAll("circle, rect")
      .attr("stroke", "#f59e0b")
      .attr("stroke-width", 3);
  },

  highlightEdge(sourceId, targetId) {
    // Reset all edges to default style
    this.edgeGroup.selectAll("path")
      .attr("stroke", d => {
        const sId = d.source.id || d.source;
        const tId = d.target.id || d.target;
        return sId === tId ? "#94a3b8" : "#94a3b8";
      })
      .attr("stroke-opacity", 0.4)
      .attr("stroke-width", 1.5);
    
    // Reset all nodes to default style
    this.nodeGroup.selectAll("circle, rect")
      .attr("stroke", "#fff")
      .attr("stroke-width", 2);
    
    // Highlight the clicked edge
    this.edgeGroup.selectAll("path")
      .filter(d => {
        const sId = d.source.id || d.source;
        const tId = d.target.id || d.target;
        return sId === sourceId && tId === targetId;
      })
      .attr("stroke", "#f59e0b")  // Orange for highlighted
      .attr("stroke-opacity", 0.9)
      .attr("stroke-width", 3);
    
    // Highlight the source and target nodes
    this.nodeGroup.selectAll("g")
      .filter(d => d.id === sourceId || d.id === targetId)
      .selectAll("circle, rect")
      .attr("stroke", "#f59e0b")
      .attr("stroke-width", 3);
  },

  findNode(nodeId) {
    return this.nodeMap ? this.nodeMap.get(nodeId) : null;
  }
};
