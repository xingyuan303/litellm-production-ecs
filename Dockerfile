# ============================================
# LiteLLM Production Dockerfile
# ============================================

# Use official LiteLLM stable image as base
FROM ghcr.io/berriai/litellm:main-stable

# Set working directory
WORKDIR /app

# Copy configuration file
COPY config.yaml /app/config.yaml

# Make entrypoint executable
RUN chmod +x ./docker/entrypoint.sh

# Expose LiteLLM port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:4000/health || exit 1

# Start LiteLLM
# Note: Remove --detailed_debug in production for better performance
CMD ["--port", "4000", "--config", "config.yaml"]
