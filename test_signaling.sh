#!/bin/bash

# Test script for JitsiSignaling package

echo "=== Testing JitsiSignaling Package ==="

cd /workspace/csett86__jitsi-meet-swift

# Build the package
echo "Building JitsiSignaling..."
swift build --package Packages/JitsiSignaling 2>&1

if [ $? -eq 0 ]; then
    echo "✅ JitsiSignaling built successfully"
else
    echo "❌ JitsiSignaling build failed"
    exit 1
fi

# Run tests
echo "Running JitsiSignaling tests..."
swift test --package Packages/JitsiSignaling 2>&1

if [ $? -eq 0 ]; then
    echo "✅ JitsiSignaling tests passed"
else
    echo "❌ JitsiSignaling tests failed"
    exit 1
fi

echo "=== All tests passed! ==="
