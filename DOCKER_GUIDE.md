# 🐳 Docker Quick Reference

## Start Dashboard
```bash
./docker-start.sh
```

## Access Dashboard
Open in your browser:
```
http://localhost:5001
```

## Useful Commands

### View Live Logs
```bash
docker-compose logs -f
```

### Check Status
```bash
docker-compose ps
```

### Stop Dashboard
```bash
./docker-stop.sh
# or
docker-compose down
```

### Restart Dashboard
```bash
docker-compose restart
```

### Rebuild (after code changes)
```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Access Container Shell
```bash
docker exec -it neat-dashboard /bin/bash
```

## Troubleshooting

### Port Already in Use
If port 5001 is in use, edit `docker-compose.yml`:
```yaml
ports:
  - "5002:5000"  # Change 5001 to 5002 or any available port
```

### Container Won't Start
Check logs:
```bash
docker-compose logs
```

### Logs Not Updating
Ensure your Erlang NEAT trainer is writing to the `logs/` directory in this folder.

### Rebuild After Changes
```bash
docker-compose down
docker-compose up -d --build
```

## How It Works

1. Docker mounts your `logs/` directory as read-only
2. Dashboard reads logs incrementally (low overhead)
3. Updates every 2 seconds
4. Accessible at http://localhost:5001

## Container Details

- **Image**: Python 3.11 slim
- **Port Mapping**: 5001 (host) → 5000 (container)
- **Volume**: `./logs:/app/logs:ro` (read-only)
- **Auto-restart**: Yes (unless stopped manually)
- **Health Check**: Every 30 seconds

## Performance

- Minimal CPU usage (~1-2%)
- Low memory footprint (~50MB)
- Efficient incremental log parsing
- No impact on training performance
