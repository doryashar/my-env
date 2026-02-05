FROM ubuntu:24.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies for setup
RUN apt-get update && apt-get install -y \
    git \
    curl \
    zsh \
    bash \
    ca-certificates \
    sudo \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create test user
RUN useradd -m -s /bin/bash testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory
WORKDIR /home/testuser

# Copy the full env repository
COPY --chown=testuser:testuser . /home/testuser/env

USER testuser

# Make test scripts executable
RUN chmod +x /home/testuser/env/tests/*.sh 2>/dev/null || true
RUN chmod +x /home/testuser/env/scripts/*.sh 2>/dev/null || true

# Run full setup test when container starts
CMD ["/bin/bash", "/home/testuser/env/tests/docker_test/full_setup_entrypoint.sh"]
