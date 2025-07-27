FROM nightscout/cgm-remote-monitor:15.0.3

# Set maintainer
LABEL maintainer="benderr"
LABEL description="Custom Nightscout deployment for personal use"

# Set working directory
WORKDIR /opt/app

# Copy any custom configuration files if needed
# COPY custom-config/ ./

# Set default environment variables (can be overridden at runtime)
ENV NODE_ENV=production
ENV INSECURE_USE_HTTP=false
ENV SECURE_HSTS_HEADER=true
ENV SECURE_HSTS_HEADER_INCLUDESUBDOMAINS=true
ENV SECURE_HSTS_HEADER_PRELOAD=true

# Expose the port
EXPOSE 1337

# Use the default entrypoint from the base image
CMD ["node", "server.js"]