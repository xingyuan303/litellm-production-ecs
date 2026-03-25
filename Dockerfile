# ============================================
# LiteLLM Production Dockerfile
# ============================================

# Use official LiteLLM image with locked version for security
# Locked version prevents supply chain attacks
# Update to latest stable version periodically: https://github.com/BerriAI/litellm/releases
FROM ghcr.io/berriai/litellm:v1.83.0

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
# Production mode (default): No detailed debug for better performance
# Debug mode: Add --detailed_debug flag for troubleshooting
CMD ["--port", "4000", "--config", "config.yaml"]
