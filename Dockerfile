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

# Create initialization script
RUN cat <<'EOF' > /docker-entrypoint-initdb.d/init.sh
#!/bin/bash
set -e

# Start MongoDB without authentication for initial setup
mongod --replSet rs0 --bind_ip_all --fork --logpath /var/log/mongodb.log

# Wait for MongoDB to start
until mongosh --eval "print('waiting...')" 2>/dev/null; do
  sleep 1
done

echo "MongoDB started"

# Initialize replica set if not already initialized
mongosh --eval '
if (rs.status().ok !== 1) {
  rs.initiate({
    _id: "rs0",
    members: [{ _id: 0, host: "localhost:27017" }]
  });
}'

# Wait for replica set to initialize
sleep 5

# Create root user if it doesn't exist
mongosh --eval '
admin = db.getSiblingDB("admin");
if (!admin.getUser("'$MONGODB_USER'")) {
  admin.createUser({
    user: "'$MONGODB_USER'",
    pwd: "'$MONGODB_PASSWORD'",
    roles: ["root"]
  });
} else {
  print("User already exists, skipping user creation");
}'

# Stop MongoDB
mongosh admin --eval "db.shutdownServer()" || true

# Wait for MongoDB to stop
while ps aux | grep -v grep | grep mongod > /dev/null; do
  sleep 1
done

echo "MongoDB stopped, ready for restart with authentication"

# Start MongoDB with authentication
exec mongod --replSet rs0 --auth --keyFile /data/mongodb/keyfile --bind_ip_all
EOF

# Make script executable
RUN chmod +x /docker-entrypoint-initdb.d/init.sh

# Set proper permissions
RUN chown -R mongodb:mongodb /data/db /docker-entrypoint-initdb.d /data/mongodb

# Expose the default MongoDB port
EXPOSE 27017

# Set the entrypoint
ENTRYPOINT ["/docker-entrypoint-initdb.d/init.sh"]
