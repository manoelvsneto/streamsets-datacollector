#!/bin/bash
set -e

echo "Starting StreamSets Data Collector ${SDC_VERSION}..."

# Start StreamSets in background
/opt/streamsets/bin/streamsets dc &
SDC_PID=$!

# Wait for StreamSets to be ready
echo "Waiting for StreamSets to start..."
for i in {1..60}; do
    if curl -f http://localhost:18630/collector/main 2>/dev/null; then
        echo "StreamSets is ready!"
        break
    fi
    echo "Waiting... ($i/60)"
    sleep 2
done

# Keep container running and forward signals
wait $SDC_PID
