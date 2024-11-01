FROM mongo:6.0.19

# Define build arguments
ARG MONGODB_USER
ARG MONGODB_PASSWORD

# Validate build arguments
RUN if [ -z "$MONGODB_USER" ] || [ -z "$MONGODB_PASSWORD" ]; then \
    echo "Error: MONGODB_USER and MONGODB_PASSWORD build arguments must be provided" && \
    exit 1; \
    fi

# Create directory for mongodb data and scripts
RUN mkdir -p /data/db /docker-entrypoint-initdb.d

# Generate keyfile for replica set authentication
RUN mkdir -p /data/mongodb && \
    openssl rand -base64 756 > /data/mongodb/keyfile && \
    chown mongodb:mongodb /data/mongodb/keyfile && \
    chmod 400 /data/mongodb/keyfile

# Create init script for replica set and root user
RUN cat <<EOF > /docker-entrypoint-initdb.d/init-replica.sh
#!/bin/bash
# Start MongoDB without auth for initial setup
mongod --replSet rs0 --bind_ip_all --keyFile /data/mongodb/keyfile &

# Wait for MongoDB to start
sleep 5

# Initialize replica set
mongosh --eval "rs.initiate({ _id: \"rs0\", members: [{ _id: 0, host: \"localhost:27017\" }]})"

# Wait for replica set to initialize
sleep 5

# Create root user using build arguments
mongosh --eval 'admin = db.getSiblingDB("admin"); admin.createUser({ user: "$MONGODB_USER", pwd: "$MONGODB_PASSWORD", roles: ["root"] })'

# Stop MongoDB
mongosh --eval "db.getSiblingDB('admin').shutdownServer()"

# Wait for MongoDB to stop
sleep 5
EOF

# Create a custom entrypoint script
RUN cat <<EOF > /custom-entrypoint.sh
#!/bin/bash
# Start MongoDB with authentication and keyfile
exec mongod --replSet rs0 --auth --bind_ip_all --keyFile /data/mongodb/keyfile
EOF

# Make scripts executable
RUN chmod +x /docker-entrypoint-initdb.d/init-replica.sh
RUN chmod +x /custom-entrypoint.sh

# Set proper permissions
RUN chown -R mongodb:mongodb /data/db /docker-entrypoint-initdb.d

# Expose the default MongoDB port
EXPOSE 27017

# Set the custom entrypoint
ENTRYPOINT ["/custom-entrypoint.sh"]
