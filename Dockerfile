# ============================================
# LiteLLM Production Dockerfile
# ============================================

# Use official LiteLLM image with main-stable tag
# main-stable tag provides latest stable release
# For locked version, check: https://github.com/BerriAI/litellm/releases
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
  CMD curl -f http://localhost:4000/health/readiness || exit 1

# Start LiteLLM
# Production mode (default): No detailed debug for better performance
# Debug mode: Add --detailed_debug flag for troubleshooting
CMD ["--port", "4000", "--config", "config.yaml"]
