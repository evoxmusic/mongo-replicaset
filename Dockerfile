FROM mongo:6.0.19

# Define build arguments
ARG MONGODB_USER
ARG MONGODB_PASSWORD

# Create directories
RUN mkdir -p /data/db /docker-entrypoint-initdb.d

# Generate keyfile for replica set authentication
RUN mkdir -p /data/mongodb && \
    openssl rand -base64 756 > /data/mongodb/keyfile && \
    chown mongodb:mongodb /data/mongodb/keyfile && \
    chmod 400 /data/mongodb/keyfile

# Create the init script
RUN cat <<'EOF' > /docker-entrypoint-initdb.d/init.sh
#!/bin/bash

mongod --bind_ip_all --replSet rs0 --keyFile /data/mongodb/keyfile &
pid=$!

echo "Waiting for MongoDB to start..."
sleep 5

echo "Initializing replica set..."
mongosh --eval 'rs.initiate({_id: "rs0", members: [{_id: 0, host: "localhost:27017"}]})'

echo "Creating admin user..."
mongosh admin --eval '
  db.createUser({
    user: "'$MONGODB_USER'",
    pwd: "'$MONGODB_PASSWORD'",
    roles: ["root"]
  })
'

# Forward SIGTERM to the MongoDB process
trap "kill -TERM $pid" SIGTERM

# Wait for MongoDB process
wait $pid
EOF

# Make script executable and set permissions
RUN chmod +x /docker-entrypoint-initdb.d/init.sh && \
    chown -R mongodb:mongodb /data/db /docker-entrypoint-initdb.d /data/mongodb

# Switch to mongodb user
USER mongodb

# Expose MongoDB port
EXPOSE 27017

# Set the entrypoint
ENTRYPOINT ["/docker-entrypoint-initdb.d/init.sh"]
